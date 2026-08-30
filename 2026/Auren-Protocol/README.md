# Auren Protocol (AU) — Smart Contract Security Audit

Security assessment performed by **Audit Rate Tech**.

## Audit Target

- **Project:** Auren Protocol
- **Token:** AU
- **Network:** BNB Smart Chain (BSC)
- **Contract:** `0x6951822a267f4ce29af8eb0db46843f585aeb352`
- **Compiler:** Solidity `0.8.14`
- **Assessment Date:** 30 August 2026
- **Audit Workspace Commit:** `0fc6217e62f5c5bf51d5a81918a9255f4b003fe9`

## Cryptographic Fingerprints

- **Source SHA-256:**  
  `83af443b151676d6978e04bd8c1a33b30309e0cc00a1b18882e19ae11e61e6dc`

- **Runtime Bytecode Keccak-256:**  
  `0x4bde947ff3a34a33a696c4efc7f648305dcebe3c64883566ca227536eb93cb54`

- **Final PDF SHA-256:**  
  `6b408962c9f81524720643d49fd47b97a7589a0b2dc7be7e31daeef1a557fed7`

## Findings

| Severity | Count |
|---|---:|
| Critical | 0 |
| High | 0 |
| Medium | 3 |
| Low | 3 |
| Informational | 1 |

## Testing Performed

- Manual smart contract security review
- Slither static analysis with manual triage
- 12 targeted Foundry security tests
- 6 fuzz properties × 256 runs
- 1,000 fee-math property runs
- On-chain configuration verification
- PancakeSwap V2 pair verification
- Source and deployed bytecode fingerprinting

## Audit Report

[View Final Security Audit Report](report/Auren_Protocol_Report.pdf)

## Source and Reproducible Tests

- [AurenProtocol.sol](src/AurenProtocol.sol)
- [Targeted Security Tests](test/AurenProtocol.t.sol)
- [Swap Security Tests](test/AurenSwap.t.sol)
- [Fuzz Tests](test/AurenFuzz.t.sol)
- [Fee Math Property Tests](test/FeeMath.t.sol)

## Important Note

The assessment found no Critical or High-severity vulnerabilities within the reviewed scope.

However, the audit identified 3 Medium, 3 Low, and 1 Informational findings. The report should therefore be interpreted as **audited with open findings**, not as a guarantee that the contract is vulnerability-free.

---

**Audit Rate Tech**  
Smart Contract Security

