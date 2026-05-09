// FSOL Lexer - Felix OS Language
// Turns raw FSOL source text into a flat stream of tokens

#[derive(Debug, PartialEq, Clone)]
pub enum Token {
    // --- FSOL Keywords ---
    Int,           // int       - initiates a function/module block
    Call,          // call      - invoke a module or driver
    Func,          // func      - declare a function mapping
    Rei,           // rei       - receive a signal or function result
    Broadcast,     // broadcast - one-time startup signal
    Dis,           // dis       - display (write to VGA/framebuffer)
    Export,        // export    - push something to another module
    Imp,           // imp       - import into a context
    Insp,          // insp      - inspect / validate
    Try,           // try       - attempt block
    If,            // if        - condition
    ElseIf,        // else if   - alternate condition
    From,          // from      - source in rei/receive
    Find,          // find      - used in pci/device scanning
    All,           // all       - universal qualifier (all func: load = true)
    Import,        // import    - pull in a module/driver from another file and load it
    Take,          // take      - grab something from a block and pipe it elsewhere
    Run,           // run       - execute directly, raw call without module system
    Command,       // command   - TTY/shell only, defines a block of shell commands
    Check,         // check     - child of insp, performs the actual validation

    // --- Symbols ---
    LParen,        // (
    RParen,        // )
    LBrace,        // {
    RBrace,        // }
    Arrow,         // ->
    Colon,         // :
    Semicolon,     // ;
    Comma,         // ,
    Equals,        // =
    Hash,          // # (comment start)
    Dot,           // .
    Minus,         // -

    // --- Literals ---
    Ident(String),    // any identifier: main, OS, TTY, i915 ...
    Number(u64),      // integer literals: 0x100, 42 ...
    StringLit(String),// string literals: "User >"
    HexLit(u64),      // hex literals: 0x7, 0x100, 0x0C03

    // --- Meta ---
    Comment(String),  // # everything after this
    Newline,
    EOF,
}

#[derive(Debug, Clone)]
pub struct Span {
    pub line: usize,
    pub col: usize,
}

#[derive(Debug, Clone)]
pub struct TokenWithSpan {
    pub token: Token,
    pub span: Span,
}

pub struct Lexer {
    source: Vec<char>,
    pos: usize,
    line: usize,
    col: usize,
}

impl Lexer {
    pub fn new(source: &str) -> Self {
        Lexer {
            source: source.chars().collect(),
            pos: 0,
            line: 1,
            col: 1,
        }
    }

    fn peek(&self) -> Option<char> {
        self.source.get(self.pos).copied()
    }

    fn peek_next(&self) -> Option<char> {
        self.source.get(self.pos + 1).copied()
    }

    fn advance(&mut self) -> Option<char> {
        let ch = self.source.get(self.pos).copied();
        if let Some(c) = ch {
            self.pos += 1;
            if c == '\n' {
                self.line += 1;
                self.col = 1;
            } else {
                self.col += 1;
            }
        }
        ch
    }

    fn current_span(&self) -> Span {
        Span { line: self.line, col: self.col }
    }

    fn skip_whitespace(&mut self) {
        while let Some(c) = self.peek() {
            if c == ' ' || c == '\t' || c == '\r' {
                self.advance();
            } else {
                break;
            }
        }
    }

    fn read_comment(&mut self) -> String {
        // consume everything after #
        let mut s = String::new();
        while let Some(c) = self.peek() {
            if c == '\n' { break; }
            s.push(c);
            self.advance();
        }
        s.trim().to_string()
    }

    fn read_string(&mut self) -> String {
        // consume opening quote already eaten by caller
        let mut s = String::new();
        while let Some(c) = self.peek() {
            self.advance();
            if c == '"' { break; }
            s.push(c);
        }
        s
    }

    fn read_number(&mut self, first: char) -> Token {
        let mut s = String::from(first);

        // check for hex prefix: 0x...
        if first == '0' {
            if let Some('x') | Some('X') = self.peek() {
                s.push(self.advance().unwrap());
                while let Some(c) = self.peek() {
                    if c.is_ascii_hexdigit() {
                        s.push(c);
                        self.advance();
                    } else {
                        break;
                    }
                }
                let val = u64::from_str_radix(&s[2..], 16).unwrap_or(0);
                return Token::HexLit(val);
            }
        }

        while let Some(c) = self.peek() {
            if c.is_ascii_digit() {
                s.push(c);
                self.advance();
            } else {
                break;
            }
        }
        Token::Number(s.parse().unwrap_or(0))
    }

    fn read_ident(&mut self, first: char) -> Token {
        let mut s = String::from(first);
        while let Some(c) = self.peek() {
            // FSOL identifiers allow letters, digits, _, -
            if c.is_alphanumeric() || c == '_' || c == '-' {
                // peek ahead: "->" is Arrow, not part of ident
                if c == '-' {
                    if self.peek_next() == Some('>') {
                        break;
                    }
                }
                s.push(c);
                self.advance();
            } else {
                break;
            }
        }

        // match keywords
        match s.as_str() {
            "int"       => Token::Int,
            "call"      => Token::Call,
            "func"      => Token::Func,
            "rei"       => Token::Rei,
            "broadcast" => Token::Broadcast,
            "dis"       => Token::Dis,
            "export"    => Token::Export,
            "imp"       => Token::Imp,
            "insp"      => Token::Insp,
            "try"       => Token::Try,
            "if"        => Token::If,
            "from"      => Token::From,
            "find"      => Token::Find,
            "all"       => Token::All,
            "import"    => Token::Import,
            "take"      => Token::Take,
            "run"       => Token::Run,
            "command"   => Token::Command,
            "check"     => Token::Check,
            _           => Token::Ident(s),
        }
    }

    pub fn tokenize(&mut self) -> Vec<TokenWithSpan> {
        let mut tokens = Vec::new();

        loop {
            self.skip_whitespace();
            let span = self.current_span();

            let ch = match self.advance() {
                Some(c) => c,
                None => {
                    tokens.push(TokenWithSpan { token: Token::EOF, span });
                    break;
                }
            };

            let token = match ch {
                '\n' => Token::Newline,
                '('  => Token::LParen,
                ')'  => Token::RParen,
                '{'  => Token::LBrace,
                '}'  => Token::RBrace,
                ':'  => Token::Colon,
                ';'  => Token::Semicolon,
                ','  => Token::Comma,
                '='  => Token::Equals,
                '.'  => Token::Dot,
                '#'  => Token::Comment(self.read_comment()),
                '"'  => Token::StringLit(self.read_string()),

                '-'  => {
                    if self.peek() == Some('>') {
                        self.advance();
                        Token::Arrow
                    } else {
                        Token::Minus
                    }
                }

                // handle "else if" as a two-word keyword
                'e'  => {
                    let t = self.read_ident('e');
                    if t == Token::Ident("else".to_string()) {
                        self.skip_whitespace();
                        if self.peek() == Some('i') {
                            let nc = self.advance().unwrap();
                            let next = self.read_ident(nc);
                            if next == Token::If {
                                Token::ElseIf
                            } else {
                                Token::Ident("else".to_string())
                            }
                        } else {
                            Token::Ident("else".to_string())
                        }
                    } else {
                        t
                    }
                }

                c if c.is_ascii_digit() => self.read_number(c),
                c if c.is_alphabetic() || c == '_' => self.read_ident(c),

                other => {
                    eprintln!("Warning: unknown char '{}' at line {} col {}",
                        other, span.line, span.col);
                    continue;
                }
            };

            tokens.push(TokenWithSpan { token, span });
        }

        tokens
    }
}
