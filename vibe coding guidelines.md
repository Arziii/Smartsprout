# Vibe Coding Guidelines for Antigravity IDE

**Version:** 1.0.0
**Target:** Multi-Platform Enterprise Ecosystem (Mobile, Web, Desktop)
**Agent Execution Context:** Antigravity IDE

---

## Table of Contents
1. [Core Philosophy & Principles](#1-core-philosophy--principles)
2. [Antigravity IDE Integration](#2-antigravity-ide-integration)
3. [Prompt Engineering Framework](#3-prompt-engineering-framework)
4. [Enterprise Workflow Standards](#4-enterprise-workflow-standards)
5. [Tech Stack Profiles](#5-tech-stack-profiles)
6. [Quality Assurance & Testing](#6-quality-assurance--testing)
7. [Error Handling & Debugging Protocol](#7-error-handling--debugging-protocol)
8. [UI/UX Consistency Framework](#8-uiux-consistency-framework)
9. [Build & Deployment Automation](#9-build--deployment-automation)
10. [Metrics & Improvement](#10-metrics--improvement)
11. [Deliverables & Templates](#11-deliverables--templates)
    - [Platform Selection Matrix](#platform-selection-matrix)
    - [Multi-Platform Architecture Templates](#multi-platform-architecture-templates)
    - [Development Phase Checklists](#development-phase-checklists)
    - [Emergency Protocols](#emergency-protocols)
    - [Context for Customization](#context-for-customization)

---

## 1. Core Philosophy & Principles

### Enterprise Vibe Coding Defined
"Vibe coding" in the enterprise is the balance between high-velocity, flow-state AI generation and rigid, scalable software architecture. It empowers developers to orchestrate broad strokes of logic and UI rapidly, while the AI strictly adheres to underlying security, platform, and architectural constraints. 

### Core Tenets
* **Platform-Agnostic First:** Core business logic is strictly decoupled from UI and platform-specific implementations. The AI must isolate state management and API layers from presentation.
* **Human-AI Symbiosis:** The AI generates, drafts, and refactors; the human steers, reviews, and approves. AI acts as a senior pair programmer, not a fully autonomous committer.
* **Quality Non-Negotiables:** Speed is permitted in UI prototyping, but zero-tolerance policies apply to type safety, security (no hardcoded secrets), and error handling.
* **Cross-Platform Consistency:** Shared architectural patterns (e.g., Clean Architecture, MVVM) must be utilized across iOS, Android, Web, and Desktop to reduce cognitive load.

---

## 2. Antigravity IDE Integration

### IDE Feature Leveraging
* **Context Windows:** AI must actively traverse the multi-root workspace to ensure shared core logic (e.g., a Rust/Kotlin Multiplatform core) aligns with the current UI file being edited.
* **File Traversal:** When modifying a shared schema, the AI must proactively suggest updating dependent platform-specific models.

### Platform Workspace Setup
* **Mobile:** Auto-configure build environments for Android Studio (Gradle daemon optimization) and Xcode (derived data management).
* **Web:** Integrate dev server commands directly into terminal prompts. Utilize hot-module-replacement (HMR) for instant feedback.
* **Desktop:** Ensure native API bindings (e.g., Windows Registry, macOS keychain) are sandboxed and mockable during development.

---

## 3. Prompt Engineering Framework

### Context-Rich Preamble
Every new feature session must begin with a system preamble establishing boundaries:
> *"Target: [Platform], Tech Stack: [Stack], Architecture: [MVVM/Clean], Strict Policies: [Accessibility/Security]."*

### Output Specifications
* **Code Formatting:** Strict adherence to platform standards (Prettier for JS/TS, SwiftLint for iOS, ktlint for Kotlin).
* **Test Coverage:** AI must supply unit tests for business logic and widget/component tests for UI immediately after code generation.

---

## 4. Enterprise Workflow Standards



### Multi-Platform Branching Strategy
* `main` -> Production.
* `develop` -> Shared core integration.
* `feature/[name]` -> Core logic updates.
* `feature/[name]-web` | `feature/[name]-ios` -> Platform-specific UI adapters.

### Security & Compliance Gates
* **No Secrets:** AI must utilize environment variables (`.env`) for all keys.
* **Review Protocol:** AI code exceeding 150 lines or modifying authentication flows triggers a **Mandatory Human Security Review**.
* **AI Confidence Threshold:** If the AI's confidence in platform-specific native APIs falls below 90%, it must halt generation, provide pseudo-code, and request human guidance.

---

## 5. Tech Stack Profiles

*Note: Configure via [Context for Customization](#context-for-customization).*

| Platform | Native Primary | Cross-Platform Primary | Shared Logic |
| :--- | :--- | :--- | :--- |
| **Mobile** | Swift / Kotlin | Flutter / React Native | Kotlin Multiplatform |
| **Web** | React / Vue (SPA) | Next.js / Nuxt (SSR/PWA) | WebAssembly (Rust) |
| **Desktop** | WPF / Swift (macOS) | Electron / Tauri | Rust / C++ |

* **Dependency Management:** Strict version pinning. No wildcard `*` or `^` versions in `package.json`, `Podfile`, or `build.gradle` without approval.

---

## 6. Quality Assurance & Testing

### Platform-Specific Testing Matrix
* **Mobile:** Unit tests for ViewModels, UI tests via Appium/Maestro across diverse screen sizes (Phone/Tablet/Foldable).
* **Web:** Playwright e2e testing across Chromium, WebKit, and Firefox. Lighthouse CI thresholds (>90 Performance/Accessibility).
* **Desktop:** Install/uninstall tests, offline capability validation, OS-specific menu bar interaction testing.

---

## 7. Error Handling & Debugging Protocol

### Standardized AI Context Parsing
When feeding errors back to the AI, use the following format:
`[Platform: iOS] [Tool: Crashlytics] [Error: EXC_BAD_ACCESS] [Trace: <paste trace>]`

### Escalation Path
If an error repeats 3 times during generation, the AI must:
1. Stop generating code.
2. Outline 3 potential root causes.
3. Suggest an alternative architectural approach or library.

---

## 8. UI/UX Consistency Framework

* **Design Tokens:** Colors, spacing, and typography must be sourced from a shared JSON/CSS-variable design token repository, never hardcoded.
* **Accessibility (A11y):**
    * *Mobile:* Minimum touch targets (44x44pt iOS, 48x48dp Android). Content descriptions mandatory.
    * *Web:* WCAG 2.1 AA compliance. `aria-` attributes validated via axe-core.
    * *Desktop:* Keyboard navigation mapping (Tab-indexing, Escape closures).

---

## 9. Build & Deployment Automation



* **CI/CD Pipeline Architecture:**
    * *Mobile:* Fastlane for automated code signing and App Store/Play Console submission.
    * *Web:* Vercel/Netlify for preview environments; AWS/GCP for production staging.
    * *Desktop:* GitHub Actions matrix builds for `.exe`, `.dmg`, `.AppImage` with code notarization.
* **Feature Flags:** All cross-platform features must be wrapped in a feature flag to allow independent platform rollouts.

---

## 10. Metrics & Improvement

* **Tracked Metrics:** AI iteration count per feature, platform-specific compilation failure rates, test coverage delta.
* **Continuous Refinement:** The AI agent logs "friction points" (e.g., struggling with a specific SwiftUI modifier) to a `friction-log.md` for weekly team review to update system prompts.

---

## 11. Deliverables & Templates

### Platform Selection Matrix

| Project Requirement | Recommended Path | Reasoning |
| :--- | :--- | :--- |
| Maximum Code Reuse, Rapid TTM | Flutter / React Native | Single UI codebase, suitable for standard forms/CRUD. |
| Deep OS Integration, Max Performance | Native (Swift/Kotlin/C++) | Direct access to hardware, minimal overhead. |
| High SEO, Linkability, Ephemeral Use | Web (SSR - Next.js) | Indexable, no install required, instant updates. |
| Offline First, Heavy Local Processing | Desktop (Tauri/Rust) | File system access, low RAM overhead, native feel. |

### Prompt Templates

**Platform Context Starter Prompt**
```text
[SYSTEM PREAMBLE]
Role: Enterprise Staff Engineer AI.
Current Context: Antigravity IDE.
Target: {PLATFORM} (e.g., Web - Next.js)
Task: {TASK_DESCRIPTION}

Constraints:
1. Maintain Clean Architecture. Isolate business logic from {PLATFORM} UI.
2. Use {STYLING_SYSTEM} for UI tokens.
3. Ensure {PLATFORM_A11Y_STANDARD} compliance.
4. Output: Provide the component code, followed by its corresponding unit test.
Generate the solution.