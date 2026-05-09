mod lexer;
mod parser;
mod codegen;
use lexer::Lexer;
use parser::Parser;
use codegen::CodeGen;

fn main() {
    let args: Vec<String> = std::env::args().collect();

    let source = if args.len() > 1 {
        std::fs::read_to_string(&args[1])
            .expect("Could not read .fsol file")
    } else {
        r#"
import VGA, Panic, UI, main, OS, i915, tty, export, list, commandfunction, disk, checkcurdir, changedir

int main() {
    call i915() {
        func: imp UI -> OS
        func: imp Panic -> OS
        func: imp VGA -> OS
    }
    int OS() {
        rei main func() {
            call insp-load check() {
                if:
                    all func: load = false
                try:
                    call Panic() {
                        dis VGA 0x7
                    }
                else if:
                    all func: load = true
                    broadcast os1 -> tty
            }
        }
    }
}
        "#.to_string()
    };

    // --- Lex ---
    let mut lexer = Lexer::new(&source);
    let tokens = lexer.tokenize();

    // --- Parse ---
    let mut parser = Parser::new(tokens);
    let ast = match parser.parse() {
        Ok(ast) => ast,
        Err(e)  => { eprintln!("Parse error: {}", e); return; }
    };

    // --- Code Generation ---
    let mut codegen = CodeGen::new();
    let asm = codegen.generate(&ast);

    // write output .asm file
    let out_path = if args.len() > 1 {
        args[1].replace(".fsol", ".asm")
    } else {
        "kernel.asm".to_string()
    };

    std::fs::write(&out_path, &asm)
        .expect("Could not write output file");

    println!("=== FSOL Compiler ===");
    println!("Input:  {}", args.get(1).map(|s| s.as_str()).unwrap_or("(built-in)"));
    println!("Output: {}", out_path);
    println!("Lines of assembly: {}", asm.lines().count());
    println!("\n--- Preview (first 40 lines) ---");
    for line in asm.lines().take(40) {
        println!("{}", line);
    }
}
