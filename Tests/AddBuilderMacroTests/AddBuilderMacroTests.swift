import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

// Macro implementations build for the host, so the corresponding module is not available when cross-compiling. Cross-compiled tests may still make use of the macro itself in end-to-end tests.
#if canImport(AddBuilderMacroMacros)
import AddBuilderMacroMacros

let testMacros: [String: Macro.Type] = [
    "AddBuilder": AddBuilderMacro.self,
]
#endif

// FIXME: This test fails, even though the syntax seems to match.
final class AddBuilderMacroTests: XCTestCase {
    func testMacro() throws {
        #if canImport(AddBuilderMacroMacros)
        assertMacroExpansion(
            """
            @AddBuilder
            struct Model {
                let a: String
                let b: Int
                let c: Bool?
            
                init(a: String, b: Int, c: Bool?) {
                    self.a = a
                    self.b = b
                    self.c = c
                }
            }
            """,
            expandedSource:
            """
            public struct Model {
                let a: String
                let b: Int
                let c: Bool?
            
                init(a: String, b: Int, c: Bool?) {
                    self.a = a
                    self.b = b
                    self.c = c
                }
            
                internal class Builder {
                    private(set) var a: String?
                    private(set) var b: Int?
                    private(set) var c: Bool?

                    internal var unsetFields: Fields {
                        var fields: Fields = []

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

                   internal var unsetRequiredFields: Fields {
                        unsetFields.intersection(Fields.required)
                    }

                   internal var isBuildable: Bool {
                        unsetRequiredFields.isEmpty
                    }

                   internal init() {}

                    @discardableResult internal func a(_ value: String) -> Self {
                        a = value

                        return self
                    }
                    @discardableResult internal func b(_ value: Int) -> Self {
                        b = value

                        return self
                    }
                    @discardableResult internal func c(_ value: Bool?) -> Self {
                        c = value

                        return self
                    }

                   internal func build() throws -> Model {
                        guard isBuildable else {
                            throw BuilderError.requiredFieldsNotSet(unsetRequiredFields)
                        }

                        return Model(a: a!, b: b!, c: c)
                    }

                    internal struct Fields: OptionSet {
                        internal let rawValue: Int

                        static internal let a = Fields(rawValue: 1 << 0)
                        static internal let b = Fields(rawValue: 1 << 1)
                        static internal let c = Fields(rawValue: 1 << 2)

                        static internal let none: Fields = []
                        static internal let required: Fields = [.a, .b]
                        static internal let optional: Fields = [.c]
                        static internal let all: Fields = [.a, .b, .c]
                    }

                   internal enum BuilderError: Error {
                        case requiredFieldsNotSet(Fields)
                    }
                }
            }
            """,
            macros: testMacros
//            ,
//            indentationWidth: .
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
