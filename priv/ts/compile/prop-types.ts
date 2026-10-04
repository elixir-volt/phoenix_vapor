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

// Parsed files, kept across components while one template compiles.
const files = new Map<string, typescript.SourceFile | undefined>()

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
      if (!files.has(path)) {
        const text = read(path)
        files.set(
          path,
          text === undefined ? undefined : typescript.createSourceFile(path, text, language)
        )
      }
      return files.get(path)
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

globalThis.__pv_literal_values = literalValues
