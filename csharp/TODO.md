# C Sharp

```cs
// VofType.cs
public enum VofType {
    Null, Bool, Int, Uint, Float, String, Data,
    // ...
}

// Vof.cs
public abstract record Vof {
    public sealed record VNull() : Vof;
    public sealed record VBool(bool Value) : Vof;
    public sealed record VInt(int Value) : Vof;
    public sealed record VDecimal(long Sig, int Places) : Vof;
    // ...
}

// Reader.cs
// Builder.cs
// Json.cs
```
