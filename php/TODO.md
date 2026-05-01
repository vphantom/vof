# PHP 8.1

PHP 8.0 support ended on 2023-11-26, so we can target 8.1

```php
namespace VOF;

// NOTE: PHP doesn't give us any means to automate the numbering. :(
enum Type: int {
    case NULL = 0;
    case BOOL = 1;
    case INT = 2;
    case UINT = 3;
    // ...
}

final class Value {
    public readonly Type $tag;
    public readonly array $args;

    public static Value $null;
    public static Value $true;
    public static Value $false;

    public function __construct(Type $tag, mixed ...$args) {
        $this->tag = $tag;
        $this->args = $args;
    }

    function as_int(Value $v): ?int {
        return match($v->tag) {
            Type::INT, Type::UINT, Type::RAW_TINT => $v->args[0],
            Type::RAW_TSTR, Type::STRING => is_numeric($v->args[0]) ? (int)$v->args[0] : null,
            default => null,
        };
    }
}
Value::$null = new Value(Type::NULL);
Value::$true = new Value(Type::BOOL, true);
Value::$false = new Value(Type::BOOL, false);

// VOF\Value::int(42);
// VOF\Reader::asInt($v);
// VOF\JSON::decode($data);
// VOF\JSON::encode($v);
```
