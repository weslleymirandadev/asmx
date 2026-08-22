// glue-bundle.mjs - assembles the renderer bundle for the test suites.
// The framework embeds wasm/glue/*.js with SEVEN consecutive incbins in
// glue.asm (nasm concatenates them at assembly time - there is no
// generated glue.js file anymore). The tests need the same concatenation,
// so this helper reproduces it IN THE SAME ORDER as the incbins in
// glue.asm (const -> state -> mount -> shell -> spa -> overlay -> boot).
// If that order changes, update BOTH glue.asm and this ORDER array.

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const GLUE_DIR = join(HERE, "..", "..", "asx", "wasm", "glue");
const ORDER = ["const", "state", "mount", "shell", "spa", "overlay", "boot"];

export const glueBundle = () =>
  ORDER.map((m) => readFileSync(join(GLUE_DIR, m + ".js"), "utf8")).join("\n");
