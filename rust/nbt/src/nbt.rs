//! Minecraft NBT 编解码与树操作（纯 Rust，无外部游戏运行时）。
//!
//! 支持两种序列化形式：
//! - 二进制：标准 Minecraft NBT。多字节数值为**大端（big-endian）**；
//!   文件通常是 gzip 流（魔数 0x1F 0x8B）包裹 NBT，也可能为裸 NBT。
//! - SNBT：Stringified NBT 文本形式（如 `{id:"minecraft:diamond",Count:1b}`）。
//!
//! 内存模型 [Nbt] 覆盖全部 12 种 TAG 类型，便于类型安全的树编辑。

use std::collections::BTreeMap;
use std::io::{Read, Write};

use serde_json::{Map, Value as Json};

// ======================== 数据模型 ========================

/// NBT 的 12 种 TAG 类型。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum TagType {
    End = 0,
    Byte = 1,
    Short = 2,
    Int = 3,
    Long = 4,
    Float = 5,
    Double = 6,
    ByteArray = 7,
    String = 8,
    List = 9,
    Compound = 10,
    IntArray = 11,
    LongArray = 12,
}

impl TagType {
    pub fn from_id(id: u8) -> Option<TagType> {
        Some(match id {
            0 => TagType::End,
            1 => TagType::Byte,
            2 => TagType::Short,
            3 => TagType::Int,
            4 => TagType::Long,
            5 => TagType::Float,
            6 => TagType::Double,
            7 => TagType::ByteArray,
            8 => TagType::String,
            9 => TagType::List,
            10 => TagType::Compound,
            11 => TagType::IntArray,
            12 => TagType::LongArray,
            _ => return None,
        })
    }

    /// 人类可读的类型名（与 AnkiNBT 的 getTagTypeName 一致）。
    pub fn name(self) -> &'static str {
        match self {
            TagType::End => "End",
            TagType::Byte => "Byte",
            TagType::Short => "Short",
            TagType::Int => "Int",
            TagType::Long => "Long",
            TagType::Float => "Float",
            TagType::Double => "Double",
            TagType::ByteArray => "Byte[]",
            TagType::String => "String",
            TagType::List => "List",
            TagType::Compound => "Compound",
            TagType::IntArray => "Int[]",
            TagType::LongArray => "Long[]",
        }
    }

    /// 从 [name]（与 [name] 方法返回一致的字符串）解析枚举；非法返回 None。
    pub fn from_name(name: &str) -> Option<TagType> {
        Some(match name {
            "End" => TagType::End,
            "Byte" => TagType::Byte,
            "Short" => TagType::Short,
            "Int" => TagType::Int,
            "Long" => TagType::Long,
            "Float" => TagType::Float,
            "Double" => TagType::Double,
            "Byte[]" => TagType::ByteArray,
            "String" => TagType::String,
            "List" => TagType::List,
            "Compound" => TagType::Compound,
            "Int[]" => TagType::IntArray,
            "Long[]" => TagType::LongArray,
            _ => return None,
        })
    }
}

/// 一个 NBT 值（含其 TAG 类型信息）。
#[derive(Debug, Clone, PartialEq)]
pub enum Nbt {
    Byte(i8),
    Short(i16),
    Int(i32),
    Long(i64),
    Float(f32),
    Double(f64),
    ByteArray(Vec<i8>),
    String(String),
    /// 列表：元素类型固定，元素序列。
    List {
        elem: TagType,
        items: Vec<Nbt>,
    },
    /// 复合：有序（按插入）的命名条目。
    Compound(BTreeMap<String, Nbt>),
    IntArray(Vec<i32>),
    LongArray(Vec<i64>),
}

impl Nbt {
    pub fn tag_type(&self) -> TagType {
        match self {
            Nbt::Byte(_) => TagType::Byte,
            Nbt::Short(_) => TagType::Short,
            Nbt::Int(_) => TagType::Int,
            Nbt::Long(_) => TagType::Long,
            Nbt::Float(_) => TagType::Float,
            Nbt::Double(_) => TagType::Double,
            Nbt::ByteArray(_) => TagType::ByteArray,
            Nbt::String(_) => TagType::String,
            Nbt::List { .. } => TagType::List,
            Nbt::Compound(_) => TagType::Compound,
            Nbt::IntArray(_) => TagType::IntArray,
            Nbt::LongArray(_) => TagType::LongArray,
        }
    }

    /// 构造一个给定类型 ID 的默认（空）值，用于"新增节点"时的占位。
    pub fn default_for(type_id: u8) -> Option<Nbt> {
        let t = TagType::from_id(type_id)?;
        Some(match t {
            TagType::End => return None,
            TagType::Byte => Nbt::Byte(0),
            TagType::Short => Nbt::Short(0),
            TagType::Int => Nbt::Int(0),
            TagType::Long => Nbt::Long(0),
            TagType::Float => Nbt::Float(0.0),
            TagType::Double => Nbt::Double(0.0),
            TagType::ByteArray => Nbt::ByteArray(Vec::new()),
            TagType::String => Nbt::String(String::new()),
            TagType::List => Nbt::List {
                elem: TagType::End,
                items: Vec::new(),
            },
            TagType::Compound => Nbt::Compound(BTreeMap::new()),
            TagType::IntArray => Nbt::IntArray(Vec::new()),
            TagType::LongArray => Nbt::LongArray(Vec::new()),
        })
    }
}

// ======================== 二进制编解码（大端） ========================

/// 检测是否为 gzip 流（魔数 0x1F 0x8B）。
fn is_gzip(data: &[u8]) -> bool {
    data.len() >= 2 && data[0] == 0x1F && data[1] == 0x8B
}

/// 解码 gzip 或裸字节为 NBT（根必须为 Compound）。
pub fn from_binary(data: &[u8]) -> Result<Nbt, String> {
    let raw: Vec<u8> = if is_gzip(data) {
        let mut decoder = flate2::read::GzDecoder::new(data);
        let mut buf = Vec::new();
        decoder
            .read_to_end(&mut buf)
            .map_err(|e| format!("gzip 解压失败: {e}"))?;
        buf
    } else {
        data.to_vec()
    };

    let mut cursor = std::io::Cursor::new(raw);
    let root_type = cursor
        .read_u8()
        .map_err(|e| format!("读取根类型失败: {e}"))?;
    if root_type != TagType::Compound as u8 {
        return Err(format!(
            "根 TAG 必须是 Compound(10)，实际为 {}",
            root_type
        ));
    }
    // 根名称（通常为空字符串）。
    let _root_name = read_string(&mut cursor)?;
    let value = read_tag(&mut cursor, TagType::Compound)?;
    Ok(value)
}

/// 编码为二进制 NBT，可选 gzip 包裹。
pub fn to_binary(nbt: &Nbt, gzip: bool) -> Result<Vec<u8>, String> {
    let mut body = Vec::new();
    // 根类型 + 根名称（空）。
    body.write_u8(TagType::Compound as u8)
        .map_err(|e| e.to_string())?;
    write_string(&mut body, "")?;
    write_tag(&mut body, nbt)?;

    if gzip {
        let mut encoder =
            flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
        encoder
            .write_all(&body)
            .map_err(|e| e.to_string())?;
        encoder.finish().map_err(|e| e.to_string())
    } else {
        Ok(body)
    }
}

fn read_tag<R: Read>(r: &mut R, ty: TagType) -> Result<Nbt, String> {
    Ok(match ty {
        TagType::End => return Err("意外的 TAG_End".to_string()),
        TagType::Byte => Nbt::Byte(r.read_i8().map_err(|e| e.to_string())?),
        TagType::Short => Nbt::Short(r.read_i16().map_err(|e| e.to_string())?),
        TagType::Int => Nbt::Int(r.read_i32().map_err(|e| e.to_string())?),
        TagType::Long => Nbt::Long(r.read_i64().map_err(|e| e.to_string())?),
        TagType::Float => Nbt::Float(r.read_f32().map_err(|e| e.to_string())?),
        TagType::Double => Nbt::Double(r.read_f64().map_err(|e| e.to_string())?),
        TagType::ByteArray => {
            let len = r.read_i32().map_err(|e| e.to_string())?;
            if len < 0 {
                return Err("ByteArray 长度无效".to_string());
            }
            let mut v = Vec::with_capacity(len as usize);
            for _ in 0..len {
                v.push(r.read_i8().map_err(|e| e.to_string())?);
            }
            Nbt::ByteArray(v)
        }
        TagType::String => Nbt::String(read_string(r)?),
        TagType::List => {
            let elem = TagType::from_id(r.read_u8().map_err(|e| e.to_string())?)
                .ok_or("List 元素类型未知")?;
            let len = r.read_i32().map_err(|e| e.to_string())?;
            if len < 0 {
                return Err("List 长度无效".to_string());
            }
            let mut items = Vec::with_capacity(len as usize);
            for _ in 0..len {
                items.push(read_tag(r, elem)?);
            }
            Nbt::List { elem, items }
        }
        TagType::Compound => {
            let mut map = BTreeMap::new();
            loop {
                let t = TagType::from_id(r.read_u8().map_err(|e| e.to_string())?)
                    .ok_or("Compound 内 TAG 类型未知")?;
                if t == TagType::End {
                    break;
                }
                let name = read_string(r)?;
                let value = read_tag(r, t)?;
                map.insert(name, value);
            }
            Nbt::Compound(map)
        }
        TagType::IntArray => {
            let len = r.read_i32().map_err(|e| e.to_string())?;
            if len < 0 {
                return Err("IntArray 长度无效".to_string());
            }
            let mut v = Vec::with_capacity(len as usize);
            for _ in 0..len {
                v.push(r.read_i32().map_err(|e| e.to_string())?);
            }
            Nbt::IntArray(v)
        }
        TagType::LongArray => {
            let len = r.read_i32().map_err(|e| e.to_string())?;
            if len < 0 {
                return Err("LongArray 长度无效".to_string());
            }
            let mut v = Vec::with_capacity(len as usize);
            for _ in 0..len {
                v.push(r.read_i64().map_err(|e| e.to_string())?);
            }
            Nbt::LongArray(v)
        }
    })
}

fn write_tag<W: Write>(w: &mut W, nbt: &Nbt) -> Result<(), String> {
    match nbt {
        Nbt::Byte(v) => w.write_i8(*v).map(|_| ()).map_err(|e| e.to_string()),
        Nbt::Short(v) => w.write_i16(*v).map(|_| ()).map_err(|e| e.to_string()),
        Nbt::Int(v) => w.write_i32(*v).map(|_| ()).map_err(|e| e.to_string()),
        Nbt::Long(v) => w.write_i64(*v).map(|_| ()).map_err(|e| e.to_string()),
        Nbt::Float(v) => w.write_f32(*v).map(|_| ()).map_err(|e| e.to_string()),
        Nbt::Double(v) => w.write_f64(*v).map(|_| ()).map_err(|e| e.to_string()),
        Nbt::ByteArray(v) => {
            w.write_i32(v.len() as i32).map_err(|e| e.to_string())?;
            for b in v {
                w.write_i8(*b).map_err(|e| e.to_string())?;
            }
            Ok(())
        }
        Nbt::String(s) => write_string(w, s),
        Nbt::List { elem, items } => {
            w.write_u8(*elem as u8).map_err(|e| e.to_string())?;
            w.write_i32(items.len() as i32).map_err(|e| e.to_string())?;
            for it in items {
                if it.tag_type() != *elem && !matches!(elem, TagType::End) {
                    // 允许空列表以 End 标记（无元素时不校验）。
                }
                write_tag(w, it)?;
            }
            Ok(())
        }
        Nbt::Compound(map) => {
            for (k, v) in map {
                w.write_u8(v.tag_type() as u8).map_err(|e| e.to_string())?;
                write_string(w, k)?;
                write_tag(w, v)?;
            }
            w.write_u8(TagType::End as u8).map_err(|e| e.to_string())
        }
        Nbt::IntArray(v) => {
            w.write_i32(v.len() as i32).map_err(|e| e.to_string())?;
            for i in v {
                w.write_i32(*i).map_err(|e| e.to_string())?;
            }
            Ok(())
        }
        Nbt::LongArray(v) => {
            w.write_i32(v.len() as i32).map_err(|e| e.to_string())?;
            for i in v {
                w.write_i64(*i).map_err(|e| e.to_string())?;
            }
            Ok(())
        }
    }
}

fn read_string<R: Read>(r: &mut R) -> Result<String, String> {
    let len = r.read_u16().map_err(|e| e.to_string())?;
    let mut buf = vec![0u8; len as usize];
    r.read_exact(&mut buf).map_err(|e| e.to_string())?;
    String::from_utf8(buf).map_err(|e| format!("NBT 字符串非 UTF-8: {e}"))
}

fn write_string<W: Write>(w: &mut W, s: &str) -> Result<(), String> {
    let bytes = s.as_bytes();
    if bytes.len() > u16::MAX as usize {
        return Err("字符串超出 u16 长度上限".to_string());
    }
    w.write_u16(bytes.len() as u16).map_err(|e| e.to_string())?;
    w.write_all(bytes).map_err(|e| e.to_string())
}

// ======================== SNBT 编解码 ========================

/// 解析 SNBT 文本为 NBT（根应为 Compound；若传入非 Compound 的单值会报错）。
pub fn from_snbt(text: &str) -> Result<Nbt, String> {
    let mut p = SnbtParser {
        chars: text.chars().peekable(),
    };
    p.skip_ws();
    let value = p.parse_value()?;
    p.skip_ws();
    if p.chars.peek().is_some() {
        return Err("SNBT 解析后有剩余字符".to_string());
    }
    Ok(value)
}

/// 将 NBT 序列化为 SNBT（紧凑形式）。
pub fn to_snbt(nbt: &Nbt) -> String {
    let mut s = String::new();
    write_snbt(nbt, &mut s);
    s
}

struct SnbtParser<'a> {
    chars: std::iter::Peekable<std::str::Chars<'a>>,
}

impl<'a> SnbtParser<'a> {
    fn skip_ws(&mut self) {
        while let Some(&c) = self.chars.peek() {
            if c.is_whitespace() {
                self.chars.next();
            } else {
                break;
            }
        }
    }

    fn peek(&mut self) -> Option<char> {
        self.chars.peek().copied()
    }

    fn next(&mut self) -> Option<char> {
        self.chars.next()
    }

    /// 解析一个值：根据首字符判断 Compound / List / 数组 / 引号字符串 / 数字 / 裸字符串。
    fn parse_value(&mut self) -> Result<Nbt, String> {
        self.skip_ws();
        match self.peek() {
            Some('{') => self.parse_compound(),
            Some('[') => self.parse_bracket(),
            Some('"') | Some('\'') => Ok(Nbt::String(self.parse_quoted_string()?)),
            Some(_) => self.parse_scalar(),
            None => Err("SNBT 意外结束".to_string()),
        }
    }

    fn parse_compound(&mut self) -> Result<Nbt, String> {
        self.next(); // {
        let mut map = BTreeMap::new();
        loop {
            self.skip_ws();
            if self.peek() == Some('}') {
                self.next();
                return Ok(Nbt::Compound(map));
            }
            let key = self.parse_key()?;
            self.skip_ws();
            if self.next() != Some(':') {
                return Err("SNBT Compound 缺少 ':'".to_string());
            }
            let value = self.parse_value()?;
            map.insert(key, value);
            self.skip_ws();
            match self.peek() {
                Some(',') => {
                    self.next();
                }
                Some('}') => {
                    self.next();
                    return Ok(Nbt::Compound(map));
                }
                _ => return Err("SNBT Compound 缺少 ',' 或 '}'".to_string()),
            }
        }
    }

    fn parse_key(&mut self) -> Result<String, String> {
        self.skip_ws();
        match self.peek() {
            Some('"') | Some('\'') => self.parse_quoted_string(),
            Some(c) if !c.is_whitespace() && c != ':' && c != ',' && c != '}' => {
                let mut s = String::new();
                while let Some(&ch) = self.chars.peek() {
                    if ch.is_whitespace() || ch == ':' || ch == ',' || ch == '}' {
                        break;
                    }
                    s.push(ch);
                    self.next();
                }
                Ok(s)
            }
            _ => Err("SNBT 非法键名".to_string()),
        }
    }

    fn parse_quoted_string(&mut self) -> Result<String, String> {
        let quote = self
            .next()
            .ok_or("SNBT 引号字符串缺少起始引号")?;
        let mut s = String::new();
        loop {
            match self.next() {
                None => return Err("SNBT 引号字符串未闭合".to_string()),
                Some('\\') => {
                    let esc = self.next().ok_or("SNBT 转义截断")?;
                    match esc {
                        'n' => s.push('\n'),
                        't' => s.push('\t'),
                        'r' => s.push('\r'),
                        '\\' => s.push('\\'),
                        '"' => s.push('"'),
                        '\'' => s.push('\''),
                        other => {
                            s.push('\\');
                            s.push(other);
                        }
                    }
                }
                Some(c) if c == quote => break,
                Some(c) => s.push(c),
            }
        }
        Ok(s)
    }

    /// 解析 [ ... ]：可能是 List（无类型前缀）、或 ByteArray/IntArray/LongArray（有 ; 类型前缀）。
    fn parse_bracket(&mut self) -> Result<Nbt, String> {
        self.next(); // [
        self.skip_ws();
        // 检测数组前缀：[I; [B; [L;（仅单字母 + 紧跟 ';' 才算，避免吞掉数字列表元素）。
        let mut has_prefix = false;
        let mut prefix = String::new();
        if let Some(c) = self.peek() {
            if matches!(c, 'I' | 'B' | 'L') {
                // 看下一字符是否为 ';'。
                let mut clone = self.chars.clone();
                clone.next();
                if clone.peek() == Some(&';') {
                    prefix.push(c);
                    self.next(); // 消费前缀字母
                    self.next(); // 消费 ';'
                    has_prefix = true;
                }
            }
        }
        if has_prefix {
            self.parse_typed_array(&prefix)
        } else {
            self.parse_list()
        }
    }

    fn parse_list(&mut self) -> Result<Nbt, String> {
        let mut items = Vec::new();
        let mut elem = TagType::End;
        loop {
            self.skip_ws();
            if self.peek() == Some(']') {
                self.next();
                return Ok(Nbt::List { elem, items });
            }
            let v = self.parse_value()?;
            if elem == TagType::End {
                elem = v.tag_type();
            }
            items.push(v);
            self.skip_ws();
            match self.peek() {
                Some(',') => {
                    self.next();
                }
                Some(']') => {
                    self.next();
                    return Ok(Nbt::List { elem, items });
                }
                _ => return Err("SNBT List 缺少 ',' 或 ']'".to_string()),
            }
        }
    }

    fn parse_typed_array(&mut self, prefix: &str) -> Result<Nbt, String> {
        let mut ints: Vec<i32> = Vec::new();
        let mut longs: Vec<i64> = Vec::new();
        let mut bytes: Vec<i8> = Vec::new();
        loop {
            self.skip_ws();
            if self.peek() == Some(']') {
                self.next();
                return match prefix {
                    "B" => Ok(Nbt::ByteArray(bytes)),
                    "I" => Ok(Nbt::IntArray(ints)),
                    "L" => Ok(Nbt::LongArray(longs)),
                    _ => Err("SNBT 未知数组前缀".to_string()),
                };
            }
            let num = self.parse_number()?;
            match prefix {
                "B" => bytes.push(num.0 as i8),
                "I" => ints.push(num.0 as i32),
                "L" => longs.push(num.0),
                _ => return Err("SNBT 未知数组前缀".to_string()),
            }
            self.skip_ws();
            match self.peek() {
                Some(',') => {
                    self.next();
                }
                Some(']') => {
                    self.next();
                    return match prefix {
                        "B" => Ok(Nbt::ByteArray(bytes)),
                        "I" => Ok(Nbt::IntArray(ints)),
                        "L" => Ok(Nbt::LongArray(longs)),
                        _ => Err("SNBT 未知数组前缀".to_string()),
                    };
                }
                _ => return Err("SNBT 数组缺少 ',' 或 ']'".to_string()),
            }
        }
    }

    /// 解析数字（返回 i64 统一表示；后缀 b/s/l/f/d 决定类型）。
    fn parse_number(&mut self) -> Result<(i64, char), String> {
        self.skip_ws();
        let mut s = String::new();
        // 允许负号。
        if self.peek() == Some('-') {
            s.push(self.next().unwrap());
        }
        while let Some(&c) = self.chars.peek() {
            if c.is_ascii_digit() || c == '.' || c == '+' || c == '-' || c == 'e' || c == 'E' {
                s.push(c);
                self.next();
            } else {
                break;
            }
        }
        // 后缀类型标记。
        let suffix = match self.peek() {
            Some(c @ ('b' | 'B' | 's' | 'S' | 'l' | 'L' | 'f' | 'F' | 'd' | 'D')) => {
                self.next();
                c
            }
            _ => 'i', // 默认 int
        };
        let raw = s.trim();
        if raw.is_empty() {
            return Err("SNBT 数字为空".to_string());
        }
        let val: i64 = raw
            .parse()
            .map_err(|_| format!("SNBT 数字解析失败: {raw}"))?;
        Ok((val, suffix))
    }

    /// 解析裸（无引号）标量：数字（带后缀）或裸字符串。
    fn parse_scalar(&mut self) -> Result<Nbt, String> {
        // 先尝试数字：看是否以数字/负号/小数点开头。
        let mut lookahead = self.chars.clone();
        let first = lookahead.next();
        let is_num = matches!(first, Some(c) if c.is_ascii_digit() || c == '-' || c == '+')
            || (first == Some('.') && matches!(lookahead.next(), Some(c) if c.is_ascii_digit()));
        if is_num {
            let (val, suffix) = self.parse_number()?;
            return match suffix.to_ascii_lowercase() {
                'b' => Ok(Nbt::Byte(val as i8)),
                's' => Ok(Nbt::Short(val as i16)),
                'l' => Ok(Nbt::Long(val)),
                'f' => Ok(Nbt::Float(val as f32)),
                'd' => Ok(Nbt::Double(val as f64)),
                _ => Ok(Nbt::Int(val as i32)),
            };
        }
        // 裸字符串：读到空白/逗号/右括号/右大括号。
        let mut s = String::new();
        while let Some(&c) = self.chars.peek() {
            if c.is_whitespace() || c == ',' || c == ']' || c == '}' || c == ':' {
                break;
            }
            s.push(c);
            self.next();
        }
        if s.is_empty() {
            return Err("SNBT 标量解析失败".to_string());
        }
        Ok(Nbt::String(s))
    }
}

fn write_snbt(nbt: &Nbt, out: &mut String) {
    match nbt {
        Nbt::Byte(v) => out.push_str(&format!("{v}b")),
        Nbt::Short(v) => out.push_str(&format!("{v}s")),
        Nbt::Int(v) => out.push_str(&format!("{v}")),
        Nbt::Long(v) => out.push_str(&format!("{v}l")),
        Nbt::Float(v) => out.push_str(&format!("{v}f")),
        Nbt::Double(v) => out.push_str(&format!("{v}d")),
        Nbt::ByteArray(v) => {
            out.push_str("[B;");
            for (i, b) in v.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                out.push_str(&format!("{b}b"));
            }
            out.push(']');
        }
        Nbt::String(s) => write_snbt_string(s, out),
        Nbt::List { elem: _, items } => {
            out.push('[');
            for (i, it) in items.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                write_snbt(it, out);
            }
            out.push(']');
        }
        Nbt::Compound(map) => {
            out.push('{');
            let mut first = true;
            for (k, v) in map {
                if !first {
                    out.push(',');
                }
                first = false;
                // 键：若是合法裸字符串则可不加引号。
                if is_bare_key(k) {
                    out.push_str(k);
                } else {
                    write_snbt_string(k, out);
                }
                out.push(':');
                write_snbt(v, out);
            }
            out.push('}');
        }
        Nbt::IntArray(v) => {
            out.push_str("[I;");
            for (i, x) in v.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                out.push_str(&format!("{x}"));
            }
            out.push(']');
        }
        Nbt::LongArray(v) => {
            out.push_str("[L;");
            for (i, x) in v.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                out.push_str(&format!("{x}l"));
            }
            out.push(']');
        }
    }
}

fn is_bare_key(s: &str) -> bool {
    if s.is_empty() {
        return false;
    }
    s.chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '.' || c == '-' || c == '/')
        && !s.chars().next().unwrap().is_ascii_digit()
}

fn write_snbt_string(s: &str, out: &mut String) {
    out.push('"');
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            '\r' => out.push_str("\\r"),
            other => out.push(other),
        }
    }
    out.push('"');
}

// ======================== 树路径操作 ========================

/// 路径：以 '/' 分隔各级；列表元素用 `[i]`（如 `items[0]` 或 `a/b[2]/c`）。
/// 返回匹配节点的可变引用（用于 set/delete）。
fn resolve_mut<'a>(root: &'a mut Nbt, path: &str) -> Result<&'a mut Nbt, String> {
    let mut cur = root;
    for seg in split_path(path) {
        cur = match cur {
            Nbt::Compound(map) => {
                let (key, idx) = split_key_index(&seg);
                match map.get_mut(key) {
                    Some(v) => {
                        if let Some(i) = idx {
                            list_index_mut(v, i)?
                        } else {
                            v
                        }
                    }
                    None => return Err(format!("路径不存在: {path}（键 {key} 缺失）")),
                }
            }
            Nbt::List { items: _, .. } => {
                let (_, idx) = split_key_index(&seg);
                match idx {
                    Some(i) => list_index_mut(cur, i)?,
                    None => return Err(format!("路径 {path} 在 List 上缺少下标")),
                }
            }
            other => return Err(format!("路径 {path} 无法在 {:?} 上继续", other.tag_type())),
        };
    }
    Ok(cur)
}

/// 只读解析（用于 get/search 遍历）。
fn resolve_ref<'a>(root: &'a Nbt, path: &str) -> Result<&'a Nbt, String> {
    let mut cur = root;
    for seg in split_path(path) {
        cur = match cur {
            Nbt::Compound(map) => {
                let (key, idx) = split_key_index(&seg);
                match map.get(key) {
                    Some(v) => {
                        if let Some(i) = idx {
                            list_index_ref(v, i)?
                        } else {
                            v
                        }
                    }
                    None => return Err(format!("路径不存在: {path}")),
                }
            }
            Nbt::List { items: _, .. } => {
                let (_, idx) = split_key_index(&seg);
                match idx {
                    Some(i) => list_index_ref(cur, i)?,
                    None => return Err(format!("路径 {path} 在 List 上缺少下标")),
                }
            }
            _ => return Err(format!("路径 {path} 无法继续")),
        };
    }
    Ok(cur)
}

fn list_index_mut<'a>(n: &'a mut Nbt, i: usize) -> Result<&'a mut Nbt, String> {
    match n {
        Nbt::List { items, .. } => items
            .get_mut(i)
            .ok_or_else(|| format!("List 下标越界: {i}")),
        _ => Err("节点不是 List，无法按下标访问".to_string()),
    }
}

fn list_index_ref<'a>(n: &'a Nbt, i: usize) -> Result<&'a Nbt, String> {
    match n {
        Nbt::List { items, .. } => items
            .get(i)
            .ok_or_else(|| format!("List 下标越界: {i}")),
        _ => Err("节点不是 List，无法按下标访问".to_string()),
    }
}

fn split_path(path: &str) -> Vec<String> {
    // 按 '/' 切分，但保留 '[i]' 与键名连在一起。
    path.split('/').map(|s| s.to_string()).collect()
}

/// 拆分 "key[3]" → ("key", Some(3))；"key" → ("key", None)。
fn split_key_index(seg: &str) -> (&str, Option<usize>) {
    if let Some(open) = seg.find('[') {
        let key = &seg[..open];
        let rest = &seg[open + 1..];
        if let Some(close) = rest.find(']') {
            let idx_str = &rest[..close];
            if let Ok(i) = idx_str.parse::<usize>() {
                return (key, Some(i));
            }
        }
        (seg, None)
    } else {
        (seg, None)
    }
}

/// 取路径处的节点，序列化为 SNBT 字符串返回。
pub fn get_path(nbt: &Nbt, path: &str) -> Result<String, String> {
    let node = resolve_ref(nbt, path)?;
    Ok(to_snbt(node))
}

/// 在路径处设置节点：value 为 SNBT 文本，解析后写入（替换）。
/// 若父路径是 Compound 且键不存在则新增；若父路径是 List 则按索引替换（不新增）。
pub fn set_path(nbt: &mut Nbt, path: &str, value_snbt: &str) -> Result<(), String> {
    let value = from_snbt(value_snbt)?;
    // 空路径：整树替换。
    if path.is_empty() {
        *nbt = value;
        return Ok(());
    }
    // 拆分出容器路径 + 末段（key[index]）。
    let (container_path, key, idx) = split_leaf(path);
    let parent = if container_path.is_empty() {
        nbt
    } else {
        resolve_mut(nbt, &container_path)?
    };
    match parent {
        Nbt::Compound(map) => {
            if key.is_empty() {
                return Err("set 缺少键名".to_string());
            }
            map.insert(key.to_string(), value);
            Ok(())
        }
        Nbt::List { items, .. } => {
            let i = idx.ok_or("List 上 set 必须提供下标")?;
            if i >= items.len() {
                return Err(format!("List 下标越界: {i}"));
            }
            items[i] = value;
            Ok(())
        }
        _ => Err("set 的父节点既非 Compound 也非 List".to_string()),
    }
}

/// 删除路径处的节点（Compound 删键 / List 按下标删元素）。
pub fn delete_path(nbt: &mut Nbt, path: &str) -> Result<(), String> {
    if path.is_empty() {
        return Err("不能删除根节点".to_string());
    }
    let (container_path, key, idx) = split_leaf(path);
    let parent = if container_path.is_empty() {
        nbt
    } else {
        resolve_mut(nbt, &container_path)?
    };
    match parent {
        Nbt::Compound(map) => {
            if key.is_empty() {
                return Err("delete 缺少键名".to_string());
            }
            if map.remove(&key).is_none() {
                return Err(format!("删除失败：键 {key} 不存在"));
            }
            Ok(())
        }
        Nbt::List { items, .. } => {
            let i = idx.ok_or("List 上 delete 必须提供下标")?;
            if i >= items.len() {
                return Err(format!("List 下标越界: {i}"));
            }
            items.remove(i);
            Ok(())
        }
        _ => Err("delete 的父节点既非 Compound 也非 List".to_string()),
    }
}

/// 把路径拆成 (容器路径, 末段键名, 末段下标)。
/// 例："a/b/list[2]" → ("a/b", "list", Some(2))；"list[0]" → ("", "list", Some(0))；"a/b" → ("a", "b", None)。
fn split_leaf(path: &str) -> (String, String, Option<usize>) {
    let (parent_path, last_seg) = match path.rsplit_once('/') {
        Some((p, l)) => (p.to_string(), l.to_string()),
        None => ("".to_string(), path.to_string()),
    };
    let (key, idx) = split_key_index(&last_seg);
    // 容器路径 = 末段的父节点路径。
    // - 末段有下标（key[i]）：容器要一直定位到该 List 节点，即 父路径 + 键名；
    // - 末段是普通键：容器即 父路径（不含键名）。
    let container = if idx.is_some() {
        if parent_path.is_empty() {
            key.to_string()
        } else {
            format!("{parent_path}/{key}")
        }
    } else {
        parent_path
    };
    (container, key.to_string(), idx)
}

/// 在 NBT 树中搜索所有"键名或字符串值"包含 substr 的路径，返回路径列表（最多 limit 条）。
pub fn search_paths(nbt: &Nbt, substr: &str, limit: usize) -> Vec<String> {
    let mut out = Vec::new();
    let needle = substr.to_lowercase();
    fn walk(node: &Nbt, prefix: &str, needle: &str, out: &mut Vec<String>, limit: usize) {
        if out.len() >= limit {
            return;
        }
        match node {
            Nbt::Compound(map) => {
                for (k, v) in map {
                    let path = if prefix.is_empty() {
                        k.clone()
                    } else {
                        format!("{prefix}/{k}")
                    };
                    if k.to_lowercase().contains(needle) {
                        out.push(path.clone());
                    }
                    walk(v, &path, needle, out, limit);
                }
            }
            Nbt::List { items, .. } => {
                for (i, v) in items.iter().enumerate() {
                    let path = format!("{prefix}[{i}]");
                    walk(v, &path, needle, out, limit);
                }
            }
            Nbt::String(s) => {
                if s.to_lowercase().contains(needle) {
                    out.push(prefix.to_string());
                }
            }
            _ => {}
        }
    }
    walk(nbt, "", &needle, &mut out, limit);
    out
}

// ======================== 树与 JSON 互转（供 UI 渲染/编辑） ========================

/// 将 NBT 转为可序列化的树节点 JSON（供 Dart UI 渲染）。
///
/// 节点结构：
/// - 标量（Byte/Short/Int/Long/Float/Double/String）：`{type, value}`
/// - 数组（ByteArray/IntArray/LongArray）：`{type, value:[int...]}`（Byte 视为 i32 便于编辑）
/// - Compound：`{type, children:[{name, ...node}...]}`
/// - List：`{type, elem_type, children:[{...node}...]}`
///
/// 根节点无 name；子节点在 Compound 中带 name，在 List 中不带 name。
pub fn to_tree(nbt: &Nbt) -> Json {
    nbt_to_json(nbt, None)
}

/// 从树节点 JSON 重建 NBT。根节点必须是 Compound（Minecraft NBT 根恒为 Compound）。
pub fn from_tree(tree: &Json) -> Result<Nbt, String> {
    json_to_nbt(tree).and_then(|n| match n {
        Nbt::Compound(_) => Ok(n),
        other => Err(format!("NBT 根必须为 Compound，得到 {:?}", other.tag_type())),
    })
}

fn nbt_to_json(nbt: &Nbt, name: Option<&str>) -> Json {
    let mut obj = Map::new();
    if let Some(n) = name {
        obj.insert("name".into(), Json::String(n.to_string()));
    }
    match nbt {
        Nbt::Byte(v) => {
            obj.insert("type".into(), Json::String("Byte".into()));
            obj.insert("value".into(), Json::Number((*v as i32).into()));
        }
        Nbt::Short(v) => {
            obj.insert("type".into(), Json::String("Short".into()));
            obj.insert("value".into(), Json::Number((*v as i32).into()));
        }
        Nbt::Int(v) => {
            obj.insert("type".into(), Json::String("Int".into()));
            obj.insert("value".into(), Json::Number((*v).into()));
        }
        Nbt::Long(v) => {
            obj.insert("type".into(), Json::String("Long".into()));
            obj.insert("value".into(), Json::String(format!("{v}")));
        }
        Nbt::Float(v) => {
            obj.insert("type".into(), Json::String("Float".into()));
            obj.insert("value".into(), Json::Number(serde_json::Number::from_f64(*v as f64).unwrap_or(0.into())));
        }
        Nbt::Double(v) => {
            obj.insert("type".into(), Json::String("Double".into()));
            obj.insert("value".into(), Json::Number(serde_json::Number::from_f64(*v).unwrap_or(0.into())));
        }
        Nbt::String(s) => {
            obj.insert("type".into(), Json::String("String".into()));
            obj.insert("value".into(), Json::String(s.clone()));
        }
        Nbt::ByteArray(arr) => {
            obj.insert("type".into(), Json::String("Byte[]".into()));
            obj.insert(
                "value".into(),
                Json::Array(arr.iter().map(|b| Json::Number((*b as i32).into())).collect()),
            );
        }
        Nbt::IntArray(arr) => {
            obj.insert("type".into(), Json::String("Int[]".into()));
            obj.insert(
                "value".into(),
                Json::Array(arr.iter().map(|x| Json::Number((*x).into())).collect()),
            );
        }
        Nbt::LongArray(arr) => {
            obj.insert("type".into(), Json::String("Long[]".into()));
            obj.insert(
                "value".into(),
                Json::Array(arr.iter().map(|x| Json::String(format!("{x}"))).collect()),
            );
        }
        Nbt::List { elem, items } => {
            obj.insert("type".into(), Json::String("List".into()));
            obj.insert("elem_type".into(), Json::String(elem.name().to_string()));
            obj.insert(
                "children".into(),
                Json::Array(items.iter().map(|v| nbt_to_json(v, None)).collect()),
            );
        }
        Nbt::Compound(map) => {
            obj.insert("type".into(), Json::String("Compound".into()));
            obj.insert(
                "children".into(),
                Json::Array(
                    map.iter()
                        .map(|(k, v)| nbt_to_json(v, Some(k)))
                        .collect(),
                ),
            );
        }
    }
    Json::Object(obj)
}

fn json_to_nbt(node: &Json) -> Result<Nbt, String> {
    let obj = node
        .as_object()
        .ok_or("树节点不是对象")?;
    let ty = obj
        .get("type")
        .and_then(|v| v.as_str())
        .ok_or("树节点缺少 type")?;
    match ty {
        "Byte" => Ok(Nbt::Byte(parse_i64_value(obj, "Byte")? as i8)),
        "Short" => Ok(Nbt::Short(parse_i64_value(obj, "Short")? as i16)),
        "Int" => Ok(Nbt::Int(parse_i64_value(obj, "Int")? as i32)),
        "Long" => Ok(Nbt::Long(parse_i64_value(obj, "Long")?)),
        "Float" => Ok(Nbt::Float(parse_f64_value(obj, "Float")? as f32)),
        "Double" => Ok(Nbt::Double(parse_f64_value(obj, "Double")?)),
        "String" => Ok(Nbt::String(
            obj.get("value")
                .and_then(|v| v.as_str())
                .ok_or("String 节点缺少 value")?
                .to_string(),
        )),
        "Byte[]" => Ok(Nbt::ByteArray(
            number_array(obj, "Byte[]")?
                .iter()
                .map(|x| *x as i8)
                .collect(),
        )),
        "Int[]" => Ok(Nbt::IntArray(number_array(obj, "Int[]")?)),
        "Long[]" => Ok(Nbt::LongArray(long_array(obj, "Long[]")?)),
        "List" => {
            let elem_name = obj
                .get("elem_type")
                .and_then(|v| v.as_str())
                .unwrap_or("Compound");
            let elem = TagType::from_name(elem_name)
                .ok_or_else(|| format!("未知 List 元素类型: {elem_name}"))?;
            let children = obj
                .get("children")
                .and_then(|v| v.as_array())
                .ok_or("List 节点缺少 children")?;
            let items: Result<Vec<Nbt>, String> =
                children.iter().map(json_to_nbt).collect();
            Ok(Nbt::List { elem, items: items? })
        }
        "Compound" => {
            let children = obj
                .get("children")
                .and_then(|v| v.as_array())
                .ok_or("Compound 节点缺少 children")?;
            let mut map = BTreeMap::new();
            for child in children {
                let name = child
                    .as_object()
                    .and_then(|o| o.get("name"))
                    .and_then(|v| v.as_str())
                    .ok_or("Compound 子节点缺少 name")?
                    .to_string();
                map.insert(name, json_to_nbt(child)?);
            }
            Ok(Nbt::Compound(map))
        }
        other => Err(format!("未知树节点类型: {other}")),
    }
}

fn parse_i64_value(obj: &Map<String, Json>, label: &str) -> Result<i64, String> {
    let v = obj
        .get("value")
        .ok_or_else(|| format!("{label} 节点缺少 value"))?;
    if let Some(n) = v.as_i64() {
        return Ok(n);
    }
    if let Some(s) = v.as_str() {
        return s
            .trim()
            .trim_end_matches(['b', 'B', 's', 'S', 'l', 'L', 'f', 'F', 'd', 'D'])
            .parse::<i64>()
            .map_err(|_| format!("{label} 值无法解析为整数: {s}"));
    }
    if let Some(f) = v.as_f64() {
        return Ok(f as i64);
    }
    Err(format!("{label} 值类型不合法"))
}

fn parse_f64_value(obj: &Map<String, Json>, label: &str) -> Result<f64, String> {
    let v = obj
        .get("value")
        .ok_or_else(|| format!("{label} 节点缺少 value"))?;
    if let Some(f) = v.as_f64() {
        return Ok(f);
    }
    if let Some(s) = v.as_str() {
        return s
            .trim()
            .trim_end_matches(['b', 'B', 's', 'S', 'l', 'L', 'f', 'F', 'd', 'D'])
            .parse::<f64>()
            .map_err(|_| format!("{label} 值无法解析为浮点: {s}"));
    }
    if let Some(n) = v.as_i64() {
        return Ok(n as f64);
    }
    Err(format!("{label} 值类型不合法"))
}

fn number_array(obj: &Map<String, Json>, label: &str) -> Result<Vec<i32>, String> {
    let arr = obj
        .get("value")
        .and_then(|v| v.as_array())
        .ok_or_else(|| format!("{label} 节点缺少 value 数组"))?;
    arr.iter()
        .map(|x| {
            x.as_i64()
                .map(|n| n as i32)
                .or_else(|| x.as_str().and_then(|s| s.trim().parse::<i32>().ok()))
                .ok_or_else(|| format!("{label} 数组元素非法: {x}"))
        })
        .collect()
}

fn long_array(obj: &Map<String, Json>, label: &str) -> Result<Vec<i64>, String> {
    let arr = obj
        .get("value")
        .and_then(|v| v.as_array())
        .ok_or_else(|| format!("{label} 节点缺少 value 数组"))?;
    arr.iter()
        .map(|x| {
            x.as_i64()
                .or_else(|| x.as_str().and_then(|s| s.trim().parse::<i64>().ok()))
                .ok_or_else(|| format!("{label} 数组元素非法: {x}"))
        })
        .collect()
}

// ======================== 小端/大端辅助（标准库已提供，这里仅封装统一错误） ========================
// 复用 std::io::{Read, Write} 的 read/write 扩展方法（大端）。

// 为 std::io::Read/Write 提供统一的（大端）读写便捷方法，错误转为 io::Error。
// 这里用 trait 扩展以避免每次手动 map_err。
trait NbtRead: Read {
    fn read_u8(&mut self) -> std::io::Result<u8> {
        let mut b = [0u8; 1];
        self.read_exact(&mut b)?;
        Ok(b[0])
    }
    fn read_u16(&mut self) -> std::io::Result<u16> {
        let mut b = [0u8; 2];
        self.read_exact(&mut b)?;
        Ok(u16::from_be_bytes(b))
    }
    fn read_i8(&mut self) -> std::io::Result<i8> {
        Ok(self.read_u8()? as i8)
    }
    fn read_i16(&mut self) -> std::io::Result<i16> {
        let mut b = [0u8; 2];
        self.read_exact(&mut b)?;
        Ok(i16::from_be_bytes(b))
    }
    fn read_i32(&mut self) -> std::io::Result<i32> {
        let mut b = [0u8; 4];
        self.read_exact(&mut b)?;
        Ok(i32::from_be_bytes(b))
    }
    fn read_i64(&mut self) -> std::io::Result<i64> {
        let mut b = [0u8; 8];
        self.read_exact(&mut b)?;
        Ok(i64::from_be_bytes(b))
    }
    fn read_f32(&mut self) -> std::io::Result<f32> {
        Ok(f32::from_be_bytes(self.read_i32()?.to_be_bytes()))
    }
    fn read_f64(&mut self) -> std::io::Result<f64> {
        Ok(f64::from_be_bytes(self.read_i64()?.to_be_bytes()))
    }
}

trait NbtWrite: Write {
    fn write_u8(&mut self, v: u8) -> std::io::Result<()> {
        self.write_all(&[v])
    }
    fn write_u16(&mut self, v: u16) -> std::io::Result<()> {
        self.write_all(&v.to_be_bytes())
    }
    fn write_i8(&mut self, v: i8) -> std::io::Result<()> {
        self.write_all(&[v as u8])
    }
    fn write_i16(&mut self, v: i16) -> std::io::Result<()> {
        self.write_all(&v.to_be_bytes())
    }
    fn write_i32(&mut self, v: i32) -> std::io::Result<()> {
        self.write_all(&v.to_be_bytes())
    }
    fn write_i64(&mut self, v: i64) -> std::io::Result<()> {
        self.write_all(&v.to_be_bytes())
    }
    fn write_f32(&mut self, v: f32) -> std::io::Result<()> {
        self.write_all(&v.to_be_bytes())
    }
    fn write_f64(&mut self, v: f64) -> std::io::Result<()> {
        self.write_all(&v.to_be_bytes())
    }
}

impl<T: Read> NbtRead for T {}
impl<T: Write> NbtWrite for T {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn snbt_roundtrip_simple() {
        let src = r#"{id:"minecraft:diamond",Count:1b,display:{Name:"hi",Lore:["a","b"]}}"#;
        let nbt = from_snbt(src).expect("parse");
        let out = to_snbt(&nbt);
        let nbt2 = from_snbt(&out).expect("reparse");
        assert_eq!(nbt, nbt2);
    }

    #[test]
    fn snbt_arrays() {
        let nbt = from_snbt("[I;1,2,3]").expect("parse int array");
        assert!(matches!(nbt, Nbt::IntArray(v) if v == vec![1,2,3]));
        let nbt = from_snbt("[B;1b,2b,-3b]").expect("parse byte array");
        assert!(matches!(nbt, Nbt::ByteArray(v) if v == vec![1,2,-3]));
        let nbt = from_snbt("[L;1l,2l]").expect("parse long array");
        assert!(matches!(nbt, Nbt::LongArray(v) if v == vec![1,2]));
    }

    #[test]
    fn binary_roundtrip_gzip() {
        // 构造一个已知 Compound，二进制化（gzip）后再解析，应一致。
        let mut map = BTreeMap::new();
        map.insert("Count".to_string(), Nbt::Byte(5));
        map.insert(
            "Name".to_string(),
            Nbt::String("测试".to_string()),
        );
        map.insert(
            "Tags".to_string(),
            Nbt::List {
                elem: TagType::String,
                items: vec![Nbt::String("a".into()), Nbt::String("b".into())],
            },
        );
        let nbt = Nbt::Compound(map);
        let bytes = to_binary(&nbt, true).expect("encode gzip");
        assert!(is_gzip(&bytes));
        let back = from_binary(&bytes).expect("decode");
        assert_eq!(nbt, back);
    }

    #[test]
    fn binary_roundtrip_raw() {
        let nbt = Nbt::Compound({
            let mut m = BTreeMap::new();
            m.insert("x".to_string(), Nbt::Int(-42));
            m
        });
        let bytes = to_binary(&nbt, false).expect("encode raw");
        assert!(!is_gzip(&bytes));
        let back = from_binary(&bytes).expect("decode");
        assert_eq!(nbt, back);
    }

    #[test]
    fn tree_get_set_delete() {
        let mut nbt = from_snbt(r#"{a:{b:1},list:[10,20]}"#).expect("parse");
        assert_eq!(get_path(&nbt, "a/b").unwrap(), "1");
        assert_eq!(get_path(&nbt, "list[1]").unwrap(), "20");
        set_path(&mut nbt, "a/b", "99").expect("set");
        assert_eq!(get_path(&nbt, "a/b").unwrap(), "99");
        set_path(&mut nbt, "a/c", r#""new""#).expect("add key");
        assert_eq!(get_path(&nbt, "a/c").unwrap(), "\"new\"");
        delete_path(&mut nbt, "list[0]").expect("delete list elem");
        assert_eq!(get_path(&nbt, "list[0]").unwrap(), "20");
    }

    #[test]
    fn search_finds_paths() {
        let nbt = from_snbt(r#"{Enchantments:[{id:"minecraft:sharpness"}], Name:"sword"}"#)
            .expect("parse");
        let hits = search_paths(&nbt, "sharpness", 100);
        assert!(hits.iter().any(|p| p.contains("Enchantments")));
    }

    #[test]
    fn tree_roundtrip() {
        let src = r#"{id:"minecraft:diamond",Count:1b,display:{Name:"hi",Lore:["a","b"]},Ench:[{lvl:3s}]}"#;
        let nbt = from_snbt(src).expect("parse");
        let tree = to_tree(&nbt);
        // 树 -> 回 SNBT 应保持一致（字段顺序由 BTreeMap 保证）。
        let back = from_tree(&tree).expect("from_tree");
        assert_eq!(to_snbt(&back), to_snbt(&nbt));
        // 树结构断言。
        let obj = tree.as_object().unwrap();
        assert_eq!(obj["type"], "Compound");
        let children = obj["children"].as_array().unwrap();
        assert!(children.iter().any(|c| c["name"] == "Count" && c["type"] == "Byte"));
        assert!(children.iter().any(|c| c["name"] == "display" && c["type"] == "Compound"));
    }
}
