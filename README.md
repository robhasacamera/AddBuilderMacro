# AddBuilderMacro

A very simple macro that adds a Builder class to a struct.

## Example Usage

```
@AddBuilder
struct Model {
    let a: String
    let b: Int
    let c: Bool?

    var d: Bool {
        c ?? false
    }

    init(a: String, b: Int, c: Bool?) {
        self.a = a
        self.b = b
        self.c = c
    }
}

private let model = try? Model.Builder().a("a").b(1).c(true).build()
```

## Installation

AddBuilderMacro supports Swift Package Manager. To use it add the following to your `Package.swift` file:

```
dependencies: [
    .package(name: "AddBuilderMacro", url: "https://github.com/robhasacamera/AddBuilderMacro.git", from: "0.1.0")
],
```


