# SMADirect repository contract

Keep this repository small.

## Allowed top-level shape

```text
SMADirect/
├─ lib/
├─ scripts/
├─ build/
├─ .research/
├─ .gitignore
├─ AGENTS.md
└─ README.md
```

Do not create additional top-level directories unless explicitly instructed.

Do not recreate historical organizational trees such as:

```text
Apps/
Compiler/
Conformance/
Docs/
Tests/
Tools/
Vendor/
Src/
Native/
RyuJIT/
PersistedSMA/
DirectPort/
```

Do not create directory layers merely to classify files.

## Directory meaning

`lib/` contains reusable implementation material and required native headers.

`scripts/` contains active PowerShell applications, probes, tests, build scripts, and development tools.

`build/` contains generated output only. Generated material is not source.

`.research/` contains upstream source, donor repositories, retired experiments, old receipts, archaeology, and temporary research material.

The repository root is for repository metadata only.

## Repository hygiene

Do not slop up this repository.

Do not:

- vendor external repositories into `lib/` or `scripts/`;
- copy research trees into the active source tree;
- create duplicate implementations under new names;
- create `.bak`, `.old`, `.copy`, timestamped, or otherwise duplicated source files;
- place `.exe`, `.obj`, `.lib`, `.exp`, or other generated output beside source;
- create new organizational directories for tests, compilers, apps, documentation, native code, or experiments;
- preserve obsolete experiments in the active tree merely because they once produced a useful receipt;
- add frameworks, abstractions, registration systems, scaffolding, or architecture that the requested change does not require;
- reorganize unrelated files while performing a bounded task.

Reference material, donor code, archaeology, and retired work belong in `.research/`.

Generated material belongs in `build/`.

Active files must justify their presence in `lib/` or `scripts/`.

## Project direction

PowerShell remains ordinary PowerShell and executes through authentic `System.Management.Automation`.

SMADirect observes and retains the concrete runtime objects, relationships, storage, and callables that authentic SMA resolves.

Do not create a replacement PowerShell language.

Do not manually reinterpret application semantics.

Stay at the object level unless a lower representation is produced mechanically.

Prefer retaining authentic resolved objects and relationships over recreating the machinery that discovered them.

## Scope discipline

Perform the requested task and no broader cleanup unless explicitly instructed.

Do not invent a new subsystem because an existing mechanism looks imperfect.

Do not add another observation seam unless an actual reached runtime relationship cannot be identified through the existing harvest.

Do not turn a bounded receipt into permanent architecture without explicit instruction.

## Git discipline

Preserve unrelated working-tree changes.

Stage exact files only.

Never use:

```text
git add .
git add -A
```

Do not push unless explicitly instructed.

Do not reset, rewrite, delete, or normalize unrelated work merely to obtain a clean tree.