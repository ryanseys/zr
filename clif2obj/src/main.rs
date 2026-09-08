//! `clif2obj <in.clif> [--data <in.json>] -o <out.o>`: CLIF text to a
//! relocatable object for the host, with Cranelift.
//!
//! The text names every function it defines and every function and data
//! symbol it calls or takes the address of (`%name`). A name the text
//! defines is exported; a name it only uses is an import the link resolves.
//! The sidecar carries what CLIF text cannot: data objects, with their
//! bytes and relocations, and raw functions delivered as machine code.
//! Nothing here reads Ruby, and nothing here knows a runtime.

use std::collections::HashMap;
use std::path::PathBuf;

use cranelift_codegen::ir::{self, ExternalName, GlobalValueData, UserExternalName};
use cranelift_codegen::settings::{self, Configurable};
use cranelift_codegen::Context;
use cranelift_module::{DataDescription, DataId, FuncId, Linkage, Module};
use cranelift_object::{ObjectBuilder, ObjectModule};
use serde::Deserialize;

const USAGE: &str = "usage: clif2obj <in.clif> [--data <in.json>] -o <out.o>";

/// The sidecar: the backend-neutral object model's data half.
#[derive(Deserialize, Default)]
struct Sidecar {
    #[serde(default)]
    data: Vec<Data>,
    #[serde(default)]
    raw_functions: Vec<RawFunction>,
    /// Functions to keep local to the object; every other defined function
    /// is exported.
    #[serde(default)]
    local: Vec<String>,
}

#[derive(Deserialize)]
struct Data {
    name: String,
    /// `text_const` (bytes, no pointers), `data_const` (pointers, read-only
    /// after the link), `data` (writable) or `bss` (zeros).
    section: String,
    #[serde(default = "one")]
    align: u64,
    /// Hex, two digits per byte. `bss` gives `size` instead.
    #[serde(default)]
    bytes: String,
    #[serde(default)]
    size: u64,
    #[serde(default)]
    relocs: Vec<Reloc>,
    #[serde(default)]
    export: bool,
}

#[derive(Deserialize)]
struct Reloc {
    offset: u32,
    /// `abs64` is the one kind data carries.
    kind: String,
    symbol: String,
    #[serde(default)]
    addend: i64,
}

#[derive(Deserialize)]
struct RawFunction {
    name: String,
    /// Hex machine code, complete, with no relocations.
    bytes: String,
    #[serde(default = "four")]
    align: u64,
}

fn one() -> u64 {
    1
}

fn four() -> u64 {
    4
}

fn main() {
    if let Err(e) = run() {
        eprintln!("clif2obj: {e}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let mut args = std::env::args().skip(1);
    let mut input: Option<PathBuf> = None;
    let mut output: Option<PathBuf> = None;
    let mut sidecar: Option<PathBuf> = None;
    while let Some(a) = args.next() {
        match a.as_str() {
            "-o" => output = Some(args.next().ok_or(USAGE)?.into()),
            "--data" => sidecar = Some(args.next().ok_or(USAGE)?.into()),
            "-h" | "--help" => {
                println!("{USAGE}");
                return Ok(());
            }
            other if other.starts_with('-') => return Err(format!("unknown option {other:?}\n{USAGE}")),
            other => {
                if input.is_some() {
                    return Err(USAGE.to_string());
                }
                input = Some(other.into());
            }
        }
    }
    let (input, output) = (input.ok_or(USAGE)?, output.ok_or(USAGE)?);
    let text = std::fs::read_to_string(&input).map_err(|e| format!("{}: {e}", input.display()))?;
    let sidecar = match sidecar {
        Some(p) => {
            let json = std::fs::read_to_string(&p).map_err(|e| format!("{}: {e}", p.display()))?;
            serde_json::from_str::<Sidecar>(&json).map_err(|e| format!("{}: {e}", p.display()))?
        }
        None => Sidecar::default(),
    };
    let bytes = compile(&text, &sidecar)?;
    std::fs::write(&output, bytes).map_err(|e| format!("{}: {e}", output.display()))
}

fn isa() -> Result<cranelift_codegen::isa::OwnedTargetIsa, String> {
    let mut flags = settings::builder();
    for (k, v) in [
        ("opt_level", "speed"),
        ("preserve_frame_pointers", "true"),
        ("is_pic", "true"),
        ("enable_probestack", "false"),
        ("unwind_info", "false"),
    ] {
        flags.set(k, v).map_err(|e| format!("{k}: {e}"))?;
    }
    let builder = cranelift_native::builder().map_err(|e| e.to_string())?;
    builder
        .finish(settings::Flags::new(flags))
        .map_err(|e| e.to_string())
}

/// The object's bytes for `text` and `sidecar`.
fn compile(text: &str, sidecar: &Sidecar) -> Result<Vec<u8>, String> {
    let functions = cranelift_reader::parse_functions(text).map_err(|e| e.to_string())?;
    let isa = isa()?;
    let builder = ObjectBuilder::new(isa, "ze0", cranelift_module::default_libcall_names())
        .map_err(|e| e.to_string())?;
    let mut module = ObjectModule::new(builder);

    // Every name the text defines, declared first so a call between two
    // of them resolves to the definition and not to an import.
    let mut funcs: HashMap<String, FuncId> = HashMap::new();
    for f in &functions {
        let name = func_name(&f.name)?;
        let linkage = if sidecar.local.iter().any(|l| *l == name) {
            Linkage::Local
        } else {
            Linkage::Export
        };
        let id = module
            .declare_function(&name, linkage, &f.signature)
            .map_err(|e| format!("{name}: {e}"))?;
        funcs.insert(name, id);
    }
    let mut datas: HashMap<String, DataId> = HashMap::new();
    for d in &sidecar.data {
        let (writable, zeros) = match d.section.as_str() {
            "text_const" | "data_const" => (false, false),
            "data" => (true, false),
            "bss" => (true, true),
            other => return Err(format!("{}: unknown section {other:?}", d.name)),
        };
        let linkage = if d.export { Linkage::Export } else { Linkage::Local };
        let id = module
            .declare_data(&d.name, linkage, writable, false)
            .map_err(|e| format!("{}: {e}", d.name))?;
        let _ = zeros;
        datas.insert(d.name.clone(), id);
    }
    for r in &sidecar.raw_functions {
        let sig = ir::Signature::new(module.isa().default_call_conv());
        let id = module
            .declare_function(&r.name, Linkage::Export, &sig)
            .map_err(|e| format!("{}: {e}", r.name))?;
        funcs.insert(r.name.clone(), id);
    }

    // The data objects, with their relocations to functions and data.
    for d in &sidecar.data {
        let mut desc = DataDescription::new();
        if d.section == "bss" {
            desc.define_zeroinit(d.size as usize);
        } else {
            desc.define(hex(&d.bytes).map_err(|e| format!("{}: {e}", d.name))?.into_boxed_slice());
        }
        desc.set_align(d.align);
        for r in &d.relocs {
            if r.kind != "abs64" {
                return Err(format!("{}: a data relocation is abs64, not {:?}", d.name, r.kind));
            }
            if let Some(f) = funcs.get(&r.symbol) {
                let fref = module.declare_func_in_data(*f, &mut desc);
                desc.write_function_addr(r.offset, fref);
            } else if let Some(x) = datas.get(&r.symbol) {
                let gv = module.declare_data_in_data(*x, &mut desc);
                desc.write_data_addr(r.offset, gv, r.addend);
            } else {
                // A symbol the link resolves: an import.
                let id = module
                    .declare_data(&r.symbol, Linkage::Import, false, false)
                    .map_err(|e| format!("{}: {e}", r.symbol))?;
                datas.insert(r.symbol.clone(), id);
                let gv = module.declare_data_in_data(id, &mut desc);
                desc.write_data_addr(r.offset, gv, r.addend);
            }
        }
        module
            .define_data(datas[&d.name], &desc)
            .map_err(|e| format!("{}: {e}", d.name))?;
    }

    // The raw functions: machine code as given.
    for r in &sidecar.raw_functions {
        let code = hex(&r.bytes).map_err(|e| format!("{}: {e}", r.name))?;
        module
            .define_function_bytes(funcs[&r.name], r.align, &code, &[])
            .map_err(|e| format!("{}: {e}", r.name))?;
    }

    // The functions: every `%name` they reference becomes a module
    // reference, an import where the text does not define it.
    let mut ctx = Context::new();
    for mut f in functions {
        let name = func_name(&f.name)?;
        let id = funcs[&name];
        // Collect first, then rename: declaring a user name borrows the
        // function mutably while the tables are being read.
        let ext: Vec<(ir::FuncRef, String, ir::Signature)> = f
            .dfg
            .ext_funcs
            .iter()
            .map(|(fref, e)| Ok((fref, testcase_name(&e.name)?, f.dfg.signatures[e.signature].clone())))
            .collect::<Result<_, String>>()?;
        for (fref, callee, sig) in ext {
            let target = match funcs.get(&callee) {
                Some(id) => *id,
                None => {
                    let id = module
                        .declare_function(&callee, Linkage::Import, &sig)
                        .map_err(|e| format!("{callee}: {e}"))?;
                    funcs.insert(callee.clone(), id);
                    id
                }
            };
            let user = f.declare_imported_user_function(UserExternalName::new(0, target.as_u32()));
            f.dfg.ext_funcs[fref].name = ExternalName::user(user);
        }
        let syms: Vec<(ir::GlobalValue, String)> = f
            .global_values
            .iter()
            .filter_map(|(gv, data)| match data {
                GlobalValueData::Symbol { name, .. } => Some(testcase_name(name).map(|n| (gv, n))),
                _ => None,
            })
            .collect::<Result<_, String>>()?;
        for (gv, sym) in syms {
            let target = match (funcs.get(&sym), datas.get(&sym)) {
                (Some(id), _) => UserExternalName::new(0, id.as_u32()),
                (None, Some(id)) => UserExternalName::new(1, id.as_u32()),
                (None, None) => {
                    let id = module
                        .declare_data(&sym, Linkage::Import, false, false)
                        .map_err(|e| format!("{sym}: {e}"))?;
                    datas.insert(sym.clone(), id);
                    UserExternalName::new(1, id.as_u32())
                }
            };
            let user = f.declare_imported_user_function(target);
            if let GlobalValueData::Symbol { name, .. } = &mut f.global_values[gv] {
                *name = ExternalName::user(user);
            }
        }
        f.name = ir::UserFuncName::user(0, id.as_u32());
        ctx.clear();
        ctx.func = f;
        module
            .define_function(id, &mut ctx)
            .map_err(|e| format!("{name}: {e}"))?;
    }
    let product = module.finish();
    product.emit().map_err(|e| e.to_string())
}

/// The plain name behind `function %name(...)` in the text.
fn func_name(name: &ir::UserFuncName) -> Result<String, String> {
    match name {
        ir::UserFuncName::Testcase(t) => Ok(t.to_string().trim_start_matches('%').to_string()),
        other => Err(format!("a function name the text cannot spell: {other:?}")),
    }
}

/// The plain name behind `%name` in the text.
fn testcase_name(name: &ExternalName) -> Result<String, String> {
    match name {
        ExternalName::TestCase(t) => Ok(t.to_string().trim_start_matches('%').to_string()),
        other => Err(format!("a name the text cannot spell: {other:?}")),
    }
}

fn hex(text: &str) -> Result<Vec<u8>, String> {
    if text.len() % 2 != 0 {
        return Err("hex has an odd length".into());
    }
    (0..text.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&text[i..i + 2], 16).map_err(|e| e.to_string()))
        .collect()
}
