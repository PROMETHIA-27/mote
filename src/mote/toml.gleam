import gleam/bit_string
import gleam/dynamic
import gleam/result
import gleam/map

pub type TomlError {
    Tokenize(Int)
    Parse(Int)
    Semantic(SemanticError)
    BadReturn(ValidateLocation, ReturnTerm)
}

pub external type SemanticError

pub external type ValidateLocation
pub external type ReturnTerm

pub type Section = map.Map(BitString, Value)

pub type GetError {
    NotFound
    InvalidValue
}

pub type MaybeNumber {
    Integer(Int)
    Floating(Float)
    Nan
    Infinity
    NegativeInfinity
}

pub type Value {
    MaybeNumber(MaybeNumber)
    Binary(BitString)
    Boolean(Bool)
    ValueList(List(Value))
    Table(Section)
}

pub external fn parse(String) -> Result(Section, TomlError) = "tomerl" "parse"

external fn get_internal(Section, List(String)) -> Result(dynamic.Dynamic, GetError) = "tomerl" "get"

pub fn get(section: Section, path: List(String)) -> Result(Value, GetError) {
    use value <- result.try(get_internal(section, path))

    dyn_value(value) |> result.map_error(fn(_) { InvalidValue })
}

pub fn get_string(section: Section, path: List(String)) -> Result(String, GetError) {
    use value <- result.try(get(section, path))

    case value {
        Binary(str) -> case bit_string.to_string(str) {
            Ok(str) -> Ok(str)
            _ -> Error(InvalidValue)
        }
        _ -> Error(InvalidValue)
    }
}

fn dyn_value(dyn: dynamic.Dynamic) -> Result(Value, List(dynamic.DecodeError)) {
    use <- result.lazy_or({
        maybe_num(dyn) |> result.map(MaybeNumber)
    })
    use <- result.lazy_or({
        dynamic.bit_string(dyn) |> result.map(Binary)
    })
    use <- result.lazy_or({
        dynamic.bool(dyn) |> result.map(Boolean)
    })
    use <- result.lazy_or({
        dyn |> dynamic.list(dyn_value) |> result.map(ValueList)
    })
    use <- result.lazy_or({
        dyn |> dynamic.map(dynamic.bit_string, dyn_value) |> result.map(Table)
    })
    Error([dynamic.DecodeError("Value", dynamic.classify(dyn), [])])
}

fn maybe_num(dyn: dynamic.Dynamic) -> Result(MaybeNumber, List(dynamic.DecodeError)) {
    use <- result.lazy_or({
        dynamic.int(dyn) |> result.map(Integer)
    })
    use <- result.lazy_or({
        dynamic.float(dyn) |> result.map(Floating)
    })
    use <- result.lazy_or({
        use <- iff(is_atom(dyn, "nan"), Nan |> Ok)
        use <- iff(is_atom(dyn, "infinity"), Infinity |> Ok)
        use <- iff(is_atom(dyn, "negative_infinity"), NegativeInfinity |> Ok)
        Error([])
    })
    Error([dynamic.DecodeError("MaybeInt", dynamic.classify(dyn), [])])
}

external fn is_atom(dynamic.Dynamic, String) -> Bool = "mote@toml@erl" "is_atom"

fn iff(bool: Bool, then: a, else: fn() -> a) -> a {
    case bool {
        True -> then
        False -> else()
    }
}