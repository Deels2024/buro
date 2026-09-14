import fs from "node:fs";
import path from "node:path";
import Module, { createRequire } from "node:module";
import ts from "typescript";
import { fileURLToPath } from "node:url";
const require = createRequire(import.meta.url);
const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Compile the real components for Node tests; no test routes or authentication
// shortcuts are added to the application bundle.
const compile = (module, filename) => module._compile(ts.transpileModule(
  fs.readFileSync(filename, "utf8"),
  { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX, esModuleInterop: true } },
).outputText, filename);
require.extensions[".ts"] = compile;
require.extensions[".tsx"] = compile;
const filename = path.resolve(__dirname, "../app/page.tsx");
const loaded = new Module(filename);
loaded.filename = filename;
loaded.paths = Module._nodeModulePaths(path.dirname(filename));
loaded._compile(ts.transpileModule(
  fs.readFileSync(filename, "utf8") + "\nexport { AdminConsole, Claims, Support, Users, Matches, Listings, Settings, Organizations, Moderation, Dashboard };",
  { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX, esModuleInterop: true } },
).outputText, filename);
export default loaded.exports;
