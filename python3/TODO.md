# Python 3

Probably the easiest to port from Perl (keeping an eye on the OCaml original).

```python
from dataclasses import dataclass
from enum import IntEnum, auto

class T(IntEnum):
    NULL = auto()
    BOOL = auto()
    INT = auto()
    UINT = auto()
    # ...

@dataclass(frozen=True, slots=True)
class Vof:
    tag: T
    args: tuple

    def __init__(self, tag: T, *args):
        object.__setattr__(self, 'tag', tag)
        object.__setattr__(self, 'args', args)

def as_int(v: Vof) -> int | None:
    match v.tag:
        case T.INT | T.UINT | T.RAW_TINT:
            return v.d[0]
        case T.RAW_TSTR | T.STRING:
            try:
                return int(v.d[0])
            except ValueError:
                return None
        case _:
            return None

# Singletons as module-level constants, frozen by the dataclass.
# vof_bool(x) returns TRUE or FALSE, like in Perl.
NULL = Vof(T.NULL)
TRUE = Vof(T.BOOL, True)
FALSE = Vof(T.BOOL, False)

# Vof(T.INT, 42)
# Vof(T.DECIMAL, 1250, 2)
# v.tag == T.INT -> v.d[0]

# Naming is snake_case so Perl leads by example:
# vof_int(42)
# as_amount(v)

```

Possible structure:

```
vof/
    __init__.py  # re-exports
    types.py     # T enum, Vof class
    build.py     # constructors
    read.py      # readers
    helpers.py   # decimal_of_string, etc.
    json.py      # codec
```
