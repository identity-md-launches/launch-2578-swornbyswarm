# SWORN test coverage

The existing example suite is retained. `SwornBySwarm.properties.t.sol` adds
12 boundary/sequence examples and eight fuzz properties, each with 1,024 runs.
`SwornBySwarm.invariant.t.sol` extends the existing four-actor state machine to
256 sequences of 96 calls. Run counts are specified inline in the test sources.

The property selection uses the five discovery perspectives from the supplied
Pashov reference and the supplied Trail of Bits guidance on bounded inputs,
round trips, independent oracles and failure interpretation:

| Perspective | Property and coverage |
| --- | --- |
| Conservation | The sum of all four actor balances and `totalSupply()` both remain exactly `10^27`. The deployer, token, handler and zero address have no tokens after setup. |
| State transitions | Approval replaces the previous value; finite spending consumes it; the maximum allowance is unlimited. Revocation and replacement of unlimited approval take effect. Rejected operations leave the independent balance and allowance ledgers unchanged. |
| Round trips | Sending tokens out and back restores the original balances without changing approvals. Splitting a transfer has the same balance effects as a single transfer. There are no conversions or rounding rules to test. |
| Adversarial sequences | Refilling a balance does not restore spent approval. Failed balance and zero-recipient checks preserve approval for a valid retry. Every funded holder can transfer its entire balance after arbitrary preceding actions. Maximum-uint requests cannot create tokens or consume approval on failure. |
| Token-specific properties | Metadata and supply remain fixed. Zero transfers preserve balances and allowances and emit `Transfer`. Direct and delegated transfers agree for coincident or distinct owners, recipients and spenders. Zero-address restrictions and approval isolation are checked. |

The invariant handler exposes only seven targeted actions: direct transfers,
approvals, delegated transfers, boundary approvals, rejected zero-recipient
transfers, rejected zero-spender approvals and full-balance transfers. Generated
amounts deliberately include zero, one, the spendable amount, one above it and
the maximum uint256, as well as bounded and unrestricted inputs. Boundary
approvals include zero, one, the supply, maximum minus one and maximum.

The ghost ledgers start from the specified constructor supply and change only
after successful calls. They are never resynchronized from the token's observed
state. Both successful return values and expected rejection data are checked;
an arbitrary revert cannot count as a correct failure. The two tests using
`vm.prank(address(0))` check defensive guards, not a possible signer.

No new fuzz test discards inputs with `vm.assume`. No production storage or token
balances are changed with cheatcodes. The additions require no new dependencies,
forks, environment reads, FFI or configuration changes. The supplied protected launch
checks depend on the verifier's factory/pool fixtures and manifest; they are not
part of the local suite. The existing launch-flow example checks token transfers,
not actual pool initialization or swaps.

Local verification, with generated files kept in disposable scratch space:

```sh
FOUNDRY_OUT=test/scratch/out FOUNDRY_CACHE_PATH=test/scratch/cache forge build --offline
FOUNDRY_OUT=test/scratch/out FOUNDRY_CACHE_PATH=test/scratch/cache FOUNDRY_FUZZ_SEED=0x63bf4fdca190d770233c09626fe8a7be0740f9e57f3ef31b313eae3117f68a9b forge test --offline
```

Result: build successful; 56 unit/fuzz tests and three invariants passed.
Foundry 1.8 groups the invariants into one campaign and reports 57 passing tests
overall. The campaign made 24,576 calls with no unexpected handler reverts or
discarded calls. No implementation defect was found in this review or these runs.
