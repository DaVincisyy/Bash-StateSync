# Report Outline

## 1. Introduction

- course context
- project objective
- synchronization problem overview

## 2. Specification Summary

- role of directory trees `A` and `B`
- role of the synchronization journal
- expected safe behavior
- conflict handling principles

## 3. Design Approach

- Bash implementation choices
- modular organization
- conservative interpretation of ambiguous cases
- deterministic traversal strategy

## 4. Implementation Structure

- CLI and input validation
- journal management
- simple synchronization rules
- enhanced content-comparison rules
- conflict reporting

## 5. Testing Strategy

- argument parsing checks
- sample synchronization scenarios
- conflict scenarios
- edge cases such as paths with spaces

## 6. Limitations and Future Work

- unsupported cases
- known assumptions
- possible extensions if required by the specification
