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

    func setterFunc(accessLevel: String) -> String {
        """
            @discardableResult \(accessLevel) func \(paramName)(_ value: \(type)) -> Self {
                \(paramName) = value

                return self
            }
        """
    }

    func modelFieldOption(accessLevel: String, index: Int) -> String {
        "        static \(accessLevel) let \(paramName) = Fields(rawValue: 1 << \(index))"
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

    func unsetFields(accessLevel: String) -> String {
        """
            \(accessLevel) var unsetFields: Fields {
                var fields: Fields = []

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

    func setters(accessLevel: String) -> String {
        map({ $0.setterFunc(accessLevel: accessLevel) }).joined(separator: "\n")
    }

    // MARK: ModelFields

    var required: [ParamModel] {
        filter { !$0.isOptional }
    }

    var optional: [ParamModel] {
        filter { $0.isOptional }
    }

    func modelFieldOptionSet(accessLevel: String) -> String {
        """
            \(accessLevel) struct Fields: OptionSet {
                let rawValue: Int

        \(indices.map { self[$0].modelFieldOption(accessLevel: accessLevel, index: $0) }.joined(separator: "\n"))

                static \(accessLevel) let none: Fields = []
                static \(accessLevel) let required: Fields = [\(required.map { $0.fieldName }.joined(separator: ", "))]
                static \(accessLevel) let optional: Fields = [\(optional.map { $0.fieldName }.joined(separator: ", "))]
                static \(accessLevel) let all: Fields = [\(map { $0.fieldName }.joined(separator: ", "))]
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
            throw AddBuilderMacroError.onlyApplicableToStruct
        }

        let accessModifier = structDecl.modifiers.map(\.name.text).filter {
            $0 == "private"
            || $0 == "fileprivate"
            || $0 == "internal"
            || $0 == "public"
        }.first

        // we adjust the access to fileprivate if private so you can access the builder outside of the struct.
        let accessLevel = accessModifier == "private" ? "fileprivate" : accessModifier ?? "internal"

        let structName = structDecl.name.text

        // TODO: Extract the name of the struct
        var initDecl: InitializerDeclSyntax?
        var varDecls: [VariableDeclSyntax] = []

        for member in structDecl.memberBlock.members {
            if let foundInitDecl = member.decl.as(InitializerDeclSyntax.self) {
                guard initDecl == nil else {
                    throw AddBuilderMacroError.onlyAllowsSingleInitializer
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
                    throw AddBuilderMacroError.failedToFindPropertyName
                }

                guard let type = varDecl.bindings.first?.typeAnnotation?.description else {
                    throw AddBuilderMacroError.failedToFindPropertyType
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
        \(accessLevel) class Builder {
        \(params.builderVars)

        \(params.unsetFields(accessLevel: accessLevel))

           \(accessLevel) var unsetRequiredFields: Fields {
                unsetFields.intersection(Fields.required)
            }

           \(accessLevel) var isBuildable: Bool {
                unsetRequiredFields.isEmpty
            }

           \(accessLevel) init() {}

        \(params.setters(accessLevel: accessLevel))

           \(accessLevel) func build() throws -> \(structName) {
                guard isBuildable else {
                    throw BuilderError.requiredFieldsNotSet(unsetRequiredFields)
                }

                return \(structName)(\(params.initParams))
            }

        \(params.modelFieldOptionSet(accessLevel: accessLevel))

           \(accessLevel) enum BuilderError: Error {
                case requiredFieldsNotSet(Fields)
            }
        }
        """)]
    }
}

public enum AddBuilderMacroError: CustomStringConvertible, Error {
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
