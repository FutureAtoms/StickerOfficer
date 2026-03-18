/**
 * Cloud Functions export verification tests.
 *
 * Verifies that all expected Cloud Functions are exported and are
 * the correct type. Does NOT test Firestore triggers (requires emulator).
 *
 * Run: node test/exports.test.js
 */

const assert = require("assert");

// Verify the compiled module loads without errors
let funcs;
try {
  funcs = require("../lib/index");
  console.log("✓ Cloud Functions module loads successfully");
} catch (e) {
  console.error("✗ Failed to load Cloud Functions module:", e.message);
  process.exit(1);
}

// Expected function exports
const expectedFunctions = [
  "onPackPublished",
  "updateTrendingScores",
  "onLikeCreated",
  "manageChallengeStatus",
  "generateSticker",
];

// Test: all expected functions are exported
const exportedNames = Object.keys(funcs);
for (const name of expectedFunctions) {
  assert.ok(
    exportedNames.includes(name),
    `Missing export: ${name}`
  );
  console.log(`✓ ${name} is exported`);
}

// Test: no unexpected exports
for (const name of exportedNames) {
  assert.ok(
    expectedFunctions.includes(name),
    `Unexpected export: ${name}`
  );
}
console.log(`✓ No unexpected exports (${exportedNames.length} total)`);

// Test: all exports are functions (Cloud Function objects)
for (const name of expectedFunctions) {
  assert.strictEqual(
    typeof funcs[name],
    "function",
    `${name} should be a function, got ${typeof funcs[name]}`
  );
}
console.log("✓ All exports are function type");

// Test: function count matches
assert.strictEqual(
  exportedNames.length,
  expectedFunctions.length,
  `Expected ${expectedFunctions.length} exports, got ${exportedNames.length}`
);
console.log(`✓ Exactly ${expectedFunctions.length} functions exported`);

// Summary
console.log("\n✅ All Cloud Functions export tests passed!");
