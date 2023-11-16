I want three things in Zig:
1. meta data
2. interfaces/traits
3. ability to reify
because 1) the idea that meta data exists in comments or even
documentatin comments is really
absurd. [JDSL](https://thedailywtf.com/articles/the-inner-json-effect)
takes it to the extreme but the core idea is the same. With meta data
there is a structured format for *extensibility* e.g adding author,
version number to functions, line number and even specification to name a few. 2) the
advantage is mainly decoupling and *extensibility*. As an example, you
want to use a library with some object but that object doesn't have a
format function for printing, you can a) write a debug function or b)
create a wrapper type and implement format. Another pain point is when
a type has other names for the same interface like `read_money`
instead of just `read`. Then if other code relies on object syntax i.e
`object.function(...)`, I don't know of a simple way to resolve the
issue. And no union types are not a mathematical union, see the
amazing presentation by Rich Hickey [maybe
not](https://www.youtube.com/watch?v=YR5WdGrpoug&t=787s) and
[excerpt](https://www.youtube.com/watch?v=aSEQfqNYNAc). 3) reify -
"make (something abstract) more concrete or real" or what people like
to call anonymous blank, anonymous class, anonymous interface. This
goes back to the idea of meta data. The name of something is meta data
and should be treated as such by the compiler. It is **still** data
and is useful for other tools like analyzing or for stricter type
checker but should be decoupled from data. There is no need to require
a named struct to implement an interface and the only necessary
requirement is defining the functions. And also the fields of struct
should be reified. Now is Zig the only exist when defining and
accessing them via the dot notation `obj.field` but you can't store
them even though there are enums in the language and can't pass them
or call them. If I have a field and a struct, then I want to know if
the value of the field *if* it exists without by passing via strings
or only in compile time.

Clojure has a good Data model so just use it but I guess the curse of
Lisp is real.
