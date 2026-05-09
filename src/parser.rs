// FSOL Parser - Felix OS Language
// Turns the token stream from the lexer into an Abstract Syntax Tree (AST)

use crate::lexer::{Token, TokenWithSpan};

// ============================================================
//  AST Node Types
// ============================================================

#[derive(Debug, Clone)]
pub struct Program {
    pub imports: Vec<String>,       // import VGA, Panic, UI...
    pub blocks: Vec<Block>,         // top-level int blocks
}

#[derive(Debug, Clone)]
pub enum Block {
    Function(FunctionBlock),        // int main() { ... }
}

#[derive(Debug, Clone)]
pub struct FunctionBlock {
    pub name: String,
    pub body: Vec<Statement>,
}

#[derive(Debug, Clone)]
pub enum Statement {
    // call i915() { ... }
    Call {
        target: String,
        body: Vec<FuncMapping>,
    },

    // int OS() { ... }  nested function
    NestedFunction(FunctionBlock),

    // rei main func() { ... }
    Rei {
        signal: String,
        source: Option<String>,     // from OS()
        body: Vec<Statement>,
    },

    // insp-load check() { ... }
    Insp {
        kind: String,               // "load", "pci", "disk" etc
        body: Vec<InspArm>,
    },

    // broadcast os1 -> tty
    Broadcast {
        signal: String,
        target: String,
    },

    // dis VGA 0x100
    Dis {
        target: String,
        address: u64,
    },

    // export commandlist -> list
    Export {
        name: String,
        target: String,
    },

    // take command -> commandfunction
    Take {
        source: String,
        target: String,
    },

    // int list() with command { } block inside TTY
    ListBlock {
        commands: Vec<CommandEntry>,
    },

    // int commandfunction() { func: ls = list("$pwd") ... }
    CommandFunction {
        mappings: Vec<CommandMapping>,
    },

    // func: imp UI -> OS  (inside call blocks)
    FuncMapping(FuncMapping),

    // func(print{"User >"})
    Print {
        message: String,
    },
}

#[derive(Debug, Clone)]
pub struct FuncMapping {
    pub action: FuncAction,
}

#[derive(Debug, Clone)]
pub enum FuncAction {
    Imp { from: String, to: String },       // imp UI -> OS
    Assign { name: String, value: String }, // load = false
}

#[derive(Debug, Clone)]
pub enum InspArm {
    If {
        condition: Condition,
        body: Vec<Statement>,
    },
    ElseIf {
        condition: Condition,
        body: Vec<Statement>,
    },
    Try {
        body: Vec<Statement>,
    },
}

#[derive(Debug, Clone)]
pub struct Condition {
    pub qualifier: Option<String>,  // "all"
    pub lhs: String,                // "load"
    pub rhs: String,                // "true" / "false"
}

// ls - list file
#[derive(Debug, Clone)]
pub struct CommandEntry {
    pub name: String,
    pub description: String,
}

// func: ls = list("$pwd")
#[derive(Debug, Clone)]
pub struct CommandMapping {
    pub name: String,
    pub executor: String,           // list / run
    pub arg: String,
}

// ============================================================
//  Parser
// ============================================================

pub struct Parser {
    tokens: Vec<TokenWithSpan>,
    pos: usize,
}

impl Parser {
    pub fn new(tokens: Vec<TokenWithSpan>) -> Self {
        // strip newlines and comments — they're not needed for structure
        let tokens = tokens
            .into_iter()
            .filter(|t| !matches!(t.token, Token::Newline | Token::Comment(_)))
            .collect();
        Parser { tokens, pos: 0 }
    }

    // ---- token navigation ----

    fn peek(&self) -> &Token {
        self.tokens.get(self.pos)
            .map(|t| &t.token)
            .unwrap_or(&Token::EOF)
    }

    fn peek_next(&self) -> &Token {
        self.tokens.get(self.pos + 1)
            .map(|t| &t.token)
            .unwrap_or(&Token::EOF)
    }

    fn advance(&mut self) -> &Token {
        let t = self.tokens.get(self.pos)
            .map(|t| &t.token)
            .unwrap_or(&Token::EOF);
        self.pos += 1;
        t
    }

    fn expect(&mut self, expected: &Token) -> Result<(), String> {
        let t = self.peek().clone();
        if std::mem::discriminant(&t) == std::mem::discriminant(expected) {
            self.advance();
            Ok(())
        } else {
            Err(format!(
                "Expected {:?} but got {:?} at token {}",
                expected, t, self.pos
            ))
        }
    }

    fn expect_ident(&mut self) -> Result<String, String> {
        match self.peek().clone() {
            Token::Ident(s) => { self.advance(); Ok(s) }
            other => Err(format!("Expected identifier but got {:?}", other)),
        }
    }

    fn skip_parens(&mut self) {
        // skip () after function names
        if matches!(self.peek(), Token::LParen) {
            self.advance();
            if matches!(self.peek(), Token::RParen) {
                self.advance();
            }
        }
    }

    // ---- top level ----

    pub fn parse(&mut self) -> Result<Program, String> {
        let mut imports = Vec::new();
        let mut blocks = Vec::new();

        // parse import line
        if matches!(self.peek(), Token::Import) {
            self.advance();
            imports = self.parse_import_list()?;
        }

        // parse top-level int blocks
        while !matches!(self.peek(), Token::EOF) {
            match self.peek().clone() {
                Token::Int => {
                    let block = self.parse_function_block()?;
                    blocks.push(Block::Function(block));
                }
                _ => { self.advance(); } // skip unknown top-level tokens
            }
        }

        Ok(Program { imports, blocks })
    }

    fn parse_import_list(&mut self) -> Result<Vec<String>, String> {
        let mut imports = Vec::new();
        loop {
            match self.peek().clone() {
                Token::Ident(s) => { imports.push(s); self.advance(); }
                Token::Export   => { imports.push("export".to_string()); self.advance(); }
                Token::Comma    => { self.advance(); }
                _               => break,
            }
        }
        Ok(imports)
    }

    // ---- int name() { ... } ----

    fn parse_function_block(&mut self) -> Result<FunctionBlock, String> {
        self.expect(&Token::Int)?;
        let name = self.expect_ident()?;
        self.skip_parens();
        self.expect(&Token::LBrace)?;

        let body = self.parse_statements()?;

        Ok(FunctionBlock { name, body })
    }

    // parse statements until we hit a closing }
    fn parse_statements(&mut self) -> Result<Vec<Statement>, String> {
        let mut stmts = Vec::new();

        while !matches!(self.peek(), Token::RBrace | Token::EOF) {
            let stmt = self.parse_statement()?;
            stmts.push(stmt);
        }

        // consume the closing }
        if matches!(self.peek(), Token::RBrace) {
            self.advance();
        }

        Ok(stmts)
    }

    fn parse_statement(&mut self) -> Result<Statement, String> {
        match self.peek().clone() {

            // call i915() { ... }
            Token::Call => self.parse_call(),

            // int OS() { ... }  nested
            Token::Int => {
                let f = self.parse_function_block()?;
                // detect special blocks by name
                match f.name.as_str() {
                    "list" => {
                        // re-interpret body as a list block
                        let cmds = self.extract_command_entries(&f.body);
                        Ok(Statement::ListBlock { commands: cmds })
                    }
                    "commandfunction" => {
                        let mappings = self.extract_command_mappings(&f.body);
                        Ok(Statement::CommandFunction { mappings })
                    }
                    _ => Ok(Statement::NestedFunction(f))
                }
            }

            // rei os1 from OS() { ... }
            Token::Rei => self.parse_rei(),

            // broadcast os1 -> tty
            Token::Broadcast => self.parse_broadcast(),

            // dis VGA 0x100
            Token::Dis => self.parse_dis(),

            // export commandlist -> list
            Token::Export => self.parse_export(),

            // take command -> commandfunction
            Token::Take => self.parse_take(),

            // func: imp UI -> OS  or  func(print{...})
            Token::Func => self.parse_func_stmt(),

            // skip stray colons, commas, hex values, unknown tokens
            _ => {
                self.advance();
                Ok(Statement::FuncMapping(crate::parser::FuncMapping {
                    action: crate::parser::FuncAction::Assign {
                        name: "_skip".to_string(),
                        value: "_skip".to_string(),
                    }
                }))
            }
        }
    }

    // ---- call ----

    fn parse_call(&mut self) -> Result<Statement, String> {
        self.advance(); // consume 'call'

        // target may be insp-load (Ident) or Panic (Ident)
        let target = match self.peek().clone() {
            Token::Ident(s) => { self.advance(); s }
            _ => return Err("Expected identifier after call".to_string()),
        };

        // skip optional check() after insp-load
        if matches!(self.peek(), Token::Check) {
            self.advance();
        }

        self.skip_parens();

        // if no brace, it's a bare call with no body
        if !matches!(self.peek(), Token::LBrace) {
            return Ok(Statement::Call { target, body: vec![] });
        }

        self.advance(); // consume {

        // insp-load gets special parsing
        if target.starts_with("insp") {
            let kind = target
                .strip_prefix("insp-")
                .unwrap_or("unknown")
                .to_string();
            let arms = self.parse_insp_body()?;
            return Ok(Statement::Insp { kind, body: arms });
        }

        // regular call body: func: imp X -> Y lines
        let mut mappings = Vec::new();
        while !matches!(self.peek(), Token::RBrace | Token::EOF) {
            if matches!(self.peek(), Token::Func) {
                self.advance(); // func
                self.advance(); // :
                if let Ok(m) = self.parse_func_mapping() {
                    mappings.push(m);
                }
            } else {
                self.advance();
            }
        }
        if matches!(self.peek(), Token::RBrace) { self.advance(); }

        Ok(Statement::Call { target, body: mappings })
    }

    // ---- insp body: if/try/else if arms ----

    fn parse_insp_body(&mut self) -> Result<Vec<InspArm>, String> {
        let mut arms = Vec::new();

        while !matches!(self.peek(), Token::RBrace | Token::EOF) {
            match self.peek().clone() {
                Token::If => {
                    self.advance();
                    self.advance(); // :
                    let condition = self.parse_condition()?;
                    let body = self.parse_arm_body()?;
                    arms.push(InspArm::If { condition, body });
                }
                Token::ElseIf => {
                    self.advance();
                    self.advance(); // :
                    let condition = self.parse_condition()?;
                    let body = self.parse_arm_body()?;
                    arms.push(InspArm::ElseIf { condition, body });
                }
                Token::Try => {
                    self.advance();
                    self.advance(); // :
                    let body = self.parse_arm_body()?;
                    arms.push(InspArm::Try { body });
                }
                _ => { self.advance(); }
            }
        }
        if matches!(self.peek(), Token::RBrace) { self.advance(); }
        Ok(arms)
    }

    fn parse_condition(&mut self) -> Result<Condition, String> {
        // all func: load = true/false
        let qualifier = if matches!(self.peek(), Token::All) {
            self.advance();
            Some("all".to_string())
        } else {
            None
        };

        if matches!(self.peek(), Token::Func) { self.advance(); }
        if matches!(self.peek(), Token::Colon) { self.advance(); }

        let lhs = self.expect_ident()?;

        if matches!(self.peek(), Token::Equals) { self.advance(); }

        let rhs = match self.peek().clone() {
            Token::Ident(s) => { self.advance(); s }
            _ => "unknown".to_string(),
        };

        Ok(Condition { qualifier, lhs, rhs })
    }

    // parse statements until we hit next arm keyword or closing }
    fn parse_arm_body(&mut self) -> Result<Vec<Statement>, String> {
        let mut stmts = Vec::new();
        while !matches!(
            self.peek(),
            Token::If | Token::ElseIf | Token::Try | Token::RBrace | Token::EOF
        ) {
            let s = self.parse_statement()?;
            stmts.push(s);
        }
        Ok(stmts)
    }

    // ---- rei ----

    fn parse_rei(&mut self) -> Result<Statement, String> {
        self.advance(); // rei

        let signal = match self.peek().clone() {
            Token::Ident(s) => { self.advance(); s }
            Token::Func     => { self.advance(); "func".to_string() }
            other           => return Err(format!("Expected signal after rei, got {:?}", other)),
        };

        // optional: func() after signal name
        if matches!(self.peek(), Token::Func) { self.advance(); }
        self.skip_parens();

        // optional: from OS()
        let source = if matches!(self.peek(), Token::From) {
            self.advance();
            let s = self.expect_ident()?;
            self.skip_parens();
            Some(s)
        } else {
            None
        };

        self.expect(&Token::LBrace)?;
        let body = self.parse_statements()?;

        Ok(Statement::Rei { signal, source, body })
    }

    // ---- broadcast ----

    fn parse_broadcast(&mut self) -> Result<Statement, String> {
        self.advance(); // broadcast
        let signal = self.expect_ident()?;
        self.expect(&Token::Arrow)?;
        let target = self.expect_ident()?;
        Ok(Statement::Broadcast { signal, target })
    }

    // ---- dis ----

    fn parse_dis(&mut self) -> Result<Statement, String> {
        self.advance(); // dis
        let target = self.expect_ident()?;
        let address = match self.peek().clone() {
            Token::HexLit(h) => { self.advance(); h }
            Token::Number(n) => { self.advance(); n }
            _ => 0,
        };
        // skip trailing "0x7 rei, dis" junk on same conceptual line
        while matches!(self.peek(), Token::HexLit(_) | Token::Rei | Token::Comma | Token::Dis | Token::Colon) {
            self.advance();
        }
        Ok(Statement::Dis { target, address })
    }

    // ---- export ----

    fn parse_export(&mut self) -> Result<Statement, String> {
        self.advance(); // export
        let name = self.expect_ident()?;
        self.expect(&Token::Arrow)?;
        let target = self.expect_ident()?;
        Ok(Statement::Export { name, target })
    }

    // ---- take ----

    fn parse_take(&mut self) -> Result<Statement, String> {
        self.advance(); // take
        let source = match self.peek().clone() {
            Token::Command  => { self.advance(); "command".to_string() }
            Token::Ident(s) => { self.advance(); s }
            other           => return Err(format!("Expected source after take, got {:?}", other)),
        };
        self.expect(&Token::Arrow)?;
        let target = self.expect_ident()?;
        Ok(Statement::Take { source, target })
    }

    // ---- func: imp X -> Y  or  func(print{"msg"}) ----

    fn parse_func_stmt(&mut self) -> Result<Statement, String> {
        self.advance(); // func

        // func(print{"User >"})
        if matches!(self.peek(), Token::LParen) {
            self.advance(); // (
            if matches!(self.peek(), Token::Ident(_)) {
                let action = self.expect_ident()?;
                if action == "print" {
                    self.advance(); // {
                    let msg = match self.peek().clone() {
                        Token::StringLit(s) => { self.advance(); s }
                        _ => String::new(),
                    };
                    self.advance(); // }
                    self.advance(); // )
                    return Ok(Statement::Print { message: msg });
                }
            }
            // skip to closing )
            while !matches!(self.peek(), Token::RParen | Token::EOF) { self.advance(); }
            self.advance();
            return Ok(Statement::FuncMapping(FuncMapping {
                action: FuncAction::Assign {
                    name: "unknown".to_string(),
                    value: "unknown".to_string(),
                }
            }));
        }

        // func: ...
        if matches!(self.peek(), Token::Colon) { self.advance(); }

        let mapping = self.parse_func_mapping()?;
        Ok(Statement::FuncMapping(mapping))
    }

    fn parse_func_mapping(&mut self) -> Result<FuncMapping, String> {
        // imp UI -> OS
        if matches!(self.peek(), Token::Imp) {
            self.advance();
            let from = self.expect_ident()?;
            self.expect(&Token::Arrow)?;
            let to = self.expect_ident()?;
            return Ok(FuncMapping { action: FuncAction::Imp { from, to } });
        }

        // load = true / ls = list("$pwd")
        let name = self.expect_ident()?;
        if matches!(self.peek(), Token::Equals) { self.advance(); }
        let value = match self.peek().clone() {
            Token::Ident(s) => { self.advance(); s }
            Token::Run      => { self.advance(); "run".to_string() }
            Token::Call     => { self.advance(); "call".to_string() }
            Token::Import   => { self.advance(); "import".to_string() }
            _ => "unknown".to_string(),
        };
        // skip arg list
        if matches!(self.peek(), Token::LParen) {
            while !matches!(self.peek(), Token::RParen | Token::EOF) { self.advance(); }
            self.advance();
        }
        Ok(FuncMapping { action: FuncAction::Assign { name, value } })
    }

    // ---- helpers to extract list/commandfunction contents ----

    fn extract_command_entries(&self, body: &[Statement]) -> Vec<CommandEntry> {
        // The real command entries were parsed as FuncMappings with Minus tokens
        // We re-interpret them here as name-description pairs
        // For now return empty — the command block parser handles it directly
        let _ = body;
        vec![]
    }

    fn extract_command_mappings(&self, body: &[Statement]) -> Vec<CommandMapping> {
        let mut mappings = Vec::new();
        for stmt in body {
            if let Statement::FuncMapping(fm) = stmt {
                if let FuncAction::Assign { name, value } = &fm.action {
                    mappings.push(CommandMapping {
                        name: name.clone(),
                        executor: value.clone(),
                        arg: String::new(),
                    });
                }
            }
        }
        mappings
    }
}

// ============================================================
//  Pretty printer for the AST
// ============================================================

pub fn print_ast(program: &Program) {
    println!("=== FSOL AST ===\n");
    println!("Imports: {}", program.imports.join(", "));
    println!();
    for block in &program.blocks {
        match block {
            Block::Function(f) => print_function(f, 0),
        }
    }
}

fn indent(level: usize) -> String {
    "  ".repeat(level)
}

fn print_function(f: &FunctionBlock, level: usize) {
    println!("{}[int {}()]", indent(level), f.name);
    for stmt in &f.body {
        print_statement(stmt, level + 1);
    }
}

fn print_statement(stmt: &Statement, level: usize) {
    let pad = indent(level);
    match stmt {
        Statement::Call { target, body } => {
            println!("{}[call {}]", pad, target);
            for m in body {
                println!("{}  {:?}", pad, m.action);
            }
        }
        Statement::NestedFunction(f) => print_function(f, level),
        Statement::Rei { signal, source, body } => {
            match source {
                Some(s) => println!("{}[rei {} from {}]", pad, signal, s),
                None    => println!("{}[rei {}]", pad, signal),
            }
            for s in body { print_statement(s, level + 1); }
        }
        Statement::Insp { kind, body } => {
            println!("{}[insp-{} check]", pad, kind);
            for arm in body {
                match arm {
                    InspArm::If     { condition, body } => {
                        println!("{}  [if: {} {} {}]",
                            pad,
                            condition.qualifier.as_deref().unwrap_or(""),
                            condition.lhs, condition.rhs);
                        for s in body { print_statement(s, level + 2); }
                    }
                    InspArm::ElseIf { condition, body } => {
                        println!("{}  [else if: {} {} {}]",
                            pad,
                            condition.qualifier.as_deref().unwrap_or(""),
                            condition.lhs, condition.rhs);
                        for s in body { print_statement(s, level + 2); }
                    }
                    InspArm::Try    { body } => {
                        println!("{}  [try]", pad);
                        for s in body { print_statement(s, level + 2); }
                    }
                }
            }
        }
        Statement::Broadcast { signal, target } =>
            println!("{}[broadcast {} -> {}]", pad, signal, target),
        Statement::Dis { target, address } =>
            println!("{}[dis {} 0x{:X}]", pad, target, address),
        Statement::Export { name, target } =>
            println!("{}[export {} -> {}]", pad, name, target),
        Statement::Take { source, target } =>
            println!("{}[take {} -> {}]", pad, source, target),
        Statement::Print { message } =>
            println!("{}[print \"{}\"]", pad, message),
        Statement::ListBlock { commands } => {
            println!("{}[command registry]", pad);
            for c in commands {
                println!("{}  {} - {}", pad, c.name, c.description);
            }
        }
        Statement::CommandFunction { mappings } => {
            println!("{}[command implementations]", pad);
            for m in mappings {
                println!("{}  {} => {}({})", pad, m.name, m.executor, m.arg);
            }
        }
        Statement::FuncMapping(fm) => println!("{}[func {:?}]", pad, fm.action),
    }
}
