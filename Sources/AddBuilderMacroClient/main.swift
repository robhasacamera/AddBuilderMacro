import AddBuilderMacro

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

if let model {
    print(model.d)
}
