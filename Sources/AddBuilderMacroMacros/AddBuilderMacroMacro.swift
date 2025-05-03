import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Implementation of the `stringify` macro, which takes an expression
/// of any type and produces a tuple containing the value of that expression
/// and the source code that produced the value. For example
///
///     #stringify(x + y)
///
///  will expand to
///
///     (x + y, "x + y")
public struct StringifyMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) -> ExprSyntax {
        guard let argument = node.arguments.first?.expression else {
            fatalError("compiler bug: the macro does not have any arguments")
        }

        return "(\(argument), \(literal: argument.description))"
    }
}

@main
struct AddBuilderMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        AddBuilderMacro.self,
    ]
}

private struct ParamModel {
    let firstName: String
    let secondName: String?
    let type: String

    var isOptional: Bool {
        type.last == "?"
    }

    var initParamName: String {
        firstName
    }

    var initParam: String {
        "\(initParamName): \(paramName)\(isOptional ? "" : "!")"
    }

    var paramName: String {
        secondName ?? firstName
    }

    var setterFunc: String {
        """
            @discardableResult func \(paramName)(_ value: \(type)) -> Self {
                \(paramName) = value

                return self
            }
        """
    }

    func modelFieldOption(structName:String, index: Int) -> String {
        "        static let \(paramName) = \(structName)Fields(rawValue: 1 << \(index))"
    }

    var builderVar: String {
        "    private(set) var \(paramName): \(type)\(isOptional ? "" : "?")"
    }

    var fieldName: String {
        ".\(paramName)"
    }

    var unsetFieldInsertCheck: String {
        """
                if \(paramName) == nil {
                    fields.insert(\(fieldName))
                }
        """
    }
}

private extension Array where Element == ParamModel {
    // MARK: Builder

    var builderVars: String {
        map(\.builderVar).joined(separator: "\n")
    }

    func unsetFields(structName: String) -> String {
        """
            var unsetFields: \(structName)Fields {
                var fields: \(structName)Fields = []

        \(map(\.unsetFieldInsertCheck).joined(separator: "\n\n\n"))

                return fields
            }
        """
    }

    // MARK: Init Params

    var initParams: String {
        map(\.initParam).joined(separator: ", ")
    }

    // MARK: Setters

    var setters: String {
        map(\.setterFunc).joined(separator: "\n")
    }

    // MARK: ModelFields

    var required: [ParamModel] {
        filter { !$0.isOptional }
    }

    var optional: [ParamModel] {
        filter { $0.isOptional }
    }

    func modelFieldOptionSet(structName: String)-> String {
        """
            struct \(structName)Fields: OptionSet {
                let rawValue: Int

        \(indices.map { self[$0].modelFieldOption(structName: structName, index: $0) }.joined(separator: "\n"))

                static let none: \(structName)Fields = []
                static let required: \(structName)Fields = [\(required.map { $0.fieldName }.joined(separator: ", "))]
                static let optional: \(structName)Fields = [\(optional.map { $0.fieldName }.joined(separator: ", "))]
                static let all: \(structName)Fields = [\(map { $0.fieldName }.joined(separator: ", "))]
            }
        """
    }
}

// TODO: Need to ignore dynamic properties
// TODO: Need to add proper access level depending on the access of the struct
public struct AddBuilderMacro: MemberMacro {
    public static var formatMode: FormatMode { .disabled }

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration as? StructDeclSyntax else {
            throw AsyncDeclError.onlyApplicableToStruct
        }

        let structName = structDecl.name.text

        // TODO: Extract the name of the struct
        var initDecl: InitializerDeclSyntax?
        var varDecls: [VariableDeclSyntax] = []

        for member in structDecl.memberBlock.members {
            if let foundInitDecl = member.decl.as(InitializerDeclSyntax.self) {
                guard initDecl == nil else {
                    throw AsyncDeclError.onlyAllowsSingleInitializer
                }

                initDecl = foundInitDecl
            }

            if let foundVarDecl = member.decl.as(VariableDeclSyntax.self) {
                varDecls.append(foundVarDecl)
            }
        }

        var params = [ParamModel]()

        if let initDecl = initDecl {
            // TODO: Gather vars/types to create builder
            for parameter in initDecl.signature.parameterClause.parameters {
                params.append(
                    ParamModel(
                        firstName: parameter.firstName.text,
                        secondName: parameter.secondName?.text,
                        type: parameter.type.description
                    )
                )
            }
        } else {
            for varDecl in varDecls {
                guard let name = varDecl.bindings.first?.pattern.description else {
                    throw AsyncDeclError.failedToFindPropertyName
                }

                guard let type = varDecl.bindings.first?.typeAnnotation?.description else {
                    throw AsyncDeclError.failedToFindPropertyType
                }

                params.append(
                    ParamModel(
                        firstName: name,
                        secondName: nil,
                        type: type
                    )
                )
            }
        }

        return [DeclSyntax(stringLiteral: """
        class \(structName)Builder {
        \(params.builderVars)
        
        \(params.unsetFields(structName: structName))
        
            var unsetRequiredFields: \(structName)Fields {
                unsetFields.intersection(\(structName)Fields.required)
            }

            var isBuildable: Bool {
                unsetRequiredFields.isEmpty
            }

            init() {}

        \(params.setters)
        
            func build() throws -> \(structName) {
                guard isBuildable else {
                    throw \(structName)BuilderError.requiredFieldsNotSet(unsetRequiredFields)
                }

                return \(structName)(\(params.initParams))
            }
        
        \(params.modelFieldOptionSet(structName: structName))
        
            enum \(structName)BuilderError: Error {
                case requiredFieldsNotSet(\(structName)Fields)
            }
        }
        """)]
    }
}

public enum AsyncDeclError: CustomStringConvertible, Error {
    case onlyApplicableToStruct
    case onlyAllowsSingleInitializer
    case failedToFindPropertyName
    case failedToFindPropertyType

    public var description: String {
        switch self {
        case .onlyApplicableToStruct:
            "@AddBuilder can only be applied to a struct."
        case .onlyAllowsSingleInitializer:
            "@AddBuilder can only be applied to a struct with a single initializer."
        case .failedToFindPropertyName:
            "@AddBuilder could not identify a property name."
        case .failedToFindPropertyType:
            "@AddBuilder could not identify a property type."
        }
    }
}
