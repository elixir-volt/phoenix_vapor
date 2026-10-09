// Resolves the values a component's props can take, with TypeScript's own
// checker, for macro calls that read props known only when rendering. A prop
// typed as a finite set of literals, such as `"sm" | "md"` or a variant type
// derived from a tailwind-variants config, lets the macro run once per value
// at compile time.
//
// Files are read through the BEAM, so imports resolve from the project as
// they do in the browser build.

import * as typescript from "typescript"

export type Literal = string | number | boolean | null

const options: typescript.CompilerOptions = {
  target: typescript.ScriptTarget.ES2022,
  module: typescript.ModuleKind.ESNext,
  moduleResolution: typescript.ModuleResolutionKind.Bundler,
  lib: ["lib.es5.d.ts"],
  strict: true,
  noEmit: true,
  skipLibCheck: true,
  types: []
}

// Parsed files, kept across compiles until they change.
const files = new Map<string, { mtime: unknown; file: typescript.SourceFile | undefined }>()

function read(path: string): string | undefined {
  const text = Beam.callSync("read", path)
  return typeof text === "string" ? text : undefined
}

function host(entry: string, source: string, libDir: string): typescript.CompilerHost {
  return {
    fileExists: (path) => path === entry || Beam.callSync("file?", path) === true,
    directoryExists: (path) => Beam.callSync("dir?", path) === true,
    readFile: (path) => (path === entry ? source : read(path)),
    getSourceFile(path, language) {
      if (path === entry) return typescript.createSourceFile(path, source, language)
      const mtime = Beam.callSync("mtime", path)
      const cached = files.get(path)
      if (cached && cached.mtime === mtime) return cached.file

      const text = read(path)
      const file =
        text === undefined ? undefined : typescript.createSourceFile(path, text, language)
      files.set(path, { mtime, file })
      return file
    },
    getDefaultLibFileName: (options) => `${libDir}/${typescript.getDefaultLibFileName(options)}`,
    writeFile: () => {},
    getCurrentDirectory: () => "/",
    getCanonicalFileName: (path) => path,
    useCaseSensitiveFileNames: () => true,
    getNewLine: () => "\n",
    getDirectories: () => [],
    realpath: (path) => path
  }
}

function definePropsType(file: typescript.SourceFile): typescript.TypeNode | undefined {
  let found: typescript.TypeNode | undefined

  const visit = (node: typescript.Node) => {
    if (found) return
    if (
      typescript.isCallExpression(node) &&
      typescript.isIdentifier(node.expression) &&
      node.expression.text === "defineProps" &&
      node.typeArguments?.length === 1
    ) {
      found = node.typeArguments[0]
      return
    }
    typescript.forEachChild(node, visit)
  }

  visit(file)
  return found
}

function literal(checker: typescript.TypeChecker, type: typescript.Type): Literal | undefined {
  if (type.isStringLiteral() || type.isNumberLiteral()) return type.value
  if (type.flags & typescript.TypeFlags.BooleanLiteral) return checker.typeToString(type) === "true"
  if (type.flags & (typescript.TypeFlags.Undefined | typescript.TypeFlags.Null)) return null
  return undefined
}

function values(checker: typescript.TypeChecker, type: typescript.Type): Literal[] | null {
  const literals = (type.isUnion() ? type.types : [type]).map((part) => literal(checker, part))
  if (literals.some((value) => value === undefined)) return null
  return [...new Set(literals as Literal[])]
}

/**
 * The values each of `props` can take, as `defineProps<T>()` in `source`
 * declares them, or null for a prop whose type isn't a finite set of literals.
 * `entry` is where `source` is resolved from; `libDir` holds TypeScript's libs.
 */
export function literalValues(
  entry: string,
  source: string,
  props: string[],
  libDir: string
): Record<string, Literal[] | null> {
  const program = typescript.createProgram([entry], options, host(entry, source, libDir))
  const checker = program.getTypeChecker()
  const file = program.getSourceFile(entry)
  const node = file && definePropsType(file)
  const type = node && checker.getTypeFromTypeNode(node)
  const result: Record<string, Literal[] | null> = {}

  for (const prop of props) {
    const symbol = type && checker.getPropertyOfType(type, prop)
    result[prop] = symbol ? values(checker, checker.getTypeOfSymbol(symbol)) : null
  }

  return result
}

export type ExpressionType = { values: Literal[] | null; type: string }

// The names a script declares at its top level, which a template reads.
function bindings(file: typescript.SourceFile): string[] {
  const names: string[] = []

  const bind = (name: typescript.BindingName) => {
    if (typescript.isIdentifier(name)) names.push(name.text)
    else
      for (const element of name.elements)
        if (!typescript.isOmittedExpression(element)) bind(element.name)
  }

  for (const statement of file.statements) {
    if (typescript.isVariableStatement(statement))
      for (const declaration of statement.declarationList.declarations) bind(declaration.name)
    else if (typescript.isFunctionDeclaration(statement) && statement.name)
      names.push(statement.name.text)
  }

  return names
}

// Whether a name can be bound as a variable: one identifier token, not a
// keyword, as TypeScript's scanner reads it.
function identifier(name: string): boolean {
  const scanner = typescript.createScanner(typescript.ScriptTarget.ES2022, false)
  scanner.setText(name)
  return (
    scanner.scan() === typescript.SyntaxKind.Identifier &&
    scanner.scan() === typescript.SyntaxKind.EndOfFileToken
  )
}

/**
 * The values each of `expressions`, template expressions of the component
 * `source` declares, can take, with the type TypeScript gives it. They're
 * checked in a function after the script whose parameters are the script's
 * bindings as a template reads them, with refs unwrapped as Vue's
 * `ShallowUnwrapRef` does, and the props `defineProps<T>()` declares.
 */
export function expressionValues(
  entry: string,
  source: string,
  expressions: string[],
  libDir: string
): ExpressionType[] {
  const script = typescript.createSourceFile(entry, source, typescript.ScriptTarget.ES2022)
  const members = bindings(script).map((name) => `${name}: typeof ${name}`)
  const scope = [`import("vue").ShallowUnwrapRef<{ ${members.join("; ")} }>`]
  const propsType = definePropsType(script)
  if (propsType) scope.push(`(${propsType.getText(script)})`)

  // The scope's names, bindings and props, from the checker.
  const declared = `${source}\ntype __pv_Scope = ${scope.join(" & ")}\n`
  const first = typescript.createProgram([entry], options, host(entry, declared, libDir))
  const alias = first
    .getSourceFile(entry)!
    .statements.find(
      (statement) =>
        typescript.isTypeAliasDeclaration(statement) && statement.name.text === "__pv_Scope"
    )
  const names = first
    .getTypeChecker()
    .getPropertiesOfType(first.getTypeChecker().getTypeAtLocation(alias!))
    .map((symbol) => symbol.name)
    .filter(identifier)

  // A function after the script whose parameters are the scope's names, as a
  // template reads them; the alias is outside it, as they'd shadow the script's.
  const checked = [
    declared,
    `function __pv_expressions({ ${names.join(", ")} }: __pv_Scope) {`,
    ...expressions.map((expression, index) => `  const __pv_value${index} = (${expression})`),
    `}`
  ].join("\n")

  const program = typescript.createProgram([entry], options, host(entry, checked, libDir), first)
  const checker = program.getTypeChecker()
  const types = new Map<string, typescript.Type>()

  const visit = (node: typescript.Node) => {
    if (
      typescript.isVariableDeclaration(node) &&
      typescript.isIdentifier(node.name) &&
      node.name.text.startsWith("__pv_value") &&
      node.initializer
    )
      types.set(node.name.text, checker.getTypeAtLocation(node.initializer))
    typescript.forEachChild(node, visit)
  }

  visit(program.getSourceFile(entry)!)

  return expressions.map((_expression, index) => {
    const type = types.get(`__pv_value${index}`)
    return type
      ? { values: values(checker, type), type: checker.typeToString(type) }
      : { values: null, type: "unknown" }
  })
}

globalThis.__pv_literal_values = literalValues
globalThis.__pv_expression_values = expressionValues
