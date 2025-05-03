import AddBuilderMacro

// @AddBuilder
// struct Model {
//    let a: String
//    let b: Int
//    let c: Bool?
//
//    init(a: String, b: Int, c: Bool?) {
//        self.a = a
//        self.b = b
//        self.c = c
//    }
// }
//
// let model = Model(a: "a", b: 1, c: nil)

//print(model)

struct Model {
    let a: String
    let b: Int
    let c: Bool?

    init(a: String, b: Int, c: Bool?) {
        self.a = a
        self.b = b
        self.c = c
    }

    class ModelBuilder {
        private(set) var a: String?
        private(set) var b: Int?
        private(set) var c: Bool?

        var unsetFields: ModelFields {
            var fields: ModelFields = []

            if a == nil {
                fields.insert(.a)
            }

            if b == nil {
                fields.insert(.b)
            }

            if c == nil {
                fields.insert(.c)
            }

            return fields
        }

        var unsetRequiredFields: ModelFields {
            unsetFields.intersection(ModelFields.required)
        }

        var isBuildable: Bool {
            unsetRequiredFields.isEmpty
        }

        init() {}

        @discardableResult func a(_ value: String) -> Self {
            a = value

            return self
        }

        @discardableResult func b(_ value: Int) -> Self {
            b = value

            return self
        }

        @discardableResult func c(_ value: Bool?) -> Self {
            c = value

            return self
        }

        func build() throws -> Model {
            guard isBuildable else {
                throw ModelBuilderError.requiredFieldsNotSet(unsetRequiredFields)
            }

            return Model(a: a!, b: b!, c: c)
        }

        struct ModelFields: OptionSet {
            let rawValue: Int

            static let a = ModelFields(rawValue: 1 << 0)
            static let b = ModelFields(rawValue: 1 << 1)
            static let c = ModelFields(rawValue: 1 << 2)

            static let none: ModelFields = []
            static let required: ModelFields = [.a, .b]
            static let optional: ModelFields = [.c]
            static let all: ModelFields = [.a, .b, .c]
        }

        enum ModelBuilderError: Error {
            case requiredFieldsNotSet(ModelFields)
        }
    }
}
