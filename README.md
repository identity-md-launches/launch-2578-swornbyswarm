# SwornBySwarm (SWORN)

An immutable ERC-20 with **1,000,000,000 SWORN**, using 18 decimals.
The constructor mints the entire supply once to its immediate caller.

| Deployment property | Value |
| --- | --- |
| Source / Solidity identifier | `src/SwornBySwarm.sol:SwornBySwarm` |
| Name / symbol | `SwornBySwarm` / `SWORN` |
| Decimals | `18` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor ETH value | `0` |
| Initial recipient | `msg.sender`, the deploying factory on the IMD launch |
| Launch chain | Ethereum, chain ID `1` |
| Compiler / EVM | Solidity `0.8.26` / Cancun |
| Optimizer | Enabled, 200 runs |
| Metadata bytecode hash | `none` |

`INITIAL_SUPPLY` is the named constant for the supply in smallest units. There
are no other deployment parameters, external contracts, initialization calls,
linked libraries, or configuration values required by the token.

## Behavior and assumptions

The brief specifies a fixed supply and standard transfers. The implementation
therefore uses the unmodified OpenZeppelin Contracts v5.0.2 ERC-20 implementation
with one constructor mint. It has no public mint or burn functions, owner,
administrative roles, pause, blacklist, taxes, rebasing, proxy, or upgrade path.
Supply stays constant throughout the deployed contract's lifetime.

Successful `transfer`, `approve`, and `transferFrom` calls return `true`;
invalid operations revert with OpenZeppelin's ERC-6093 custom errors. Transfers
deliver exactly the specified amount. Zero-value transfers between nonzero
addresses are supported and emit `Transfer`; self-transfers preserve balances.
Zero-address recipients and spenders are rejected. A transfer does not execute
code on the receiving address.

Approvals replace the previous allowance and can be revoked with `approve(spender, 0)`.
An allowance of `type(uint256).max` is unlimited and is not decreased on spending.
All other allowances decrease on `transferFrom`, including self-transfers; a
holder using `transferFrom` also needs an allowance. `approve` emits `Approval`;
this OpenZeppelin version does not emit an additional `Approval` when
`transferFrom` spends an allowance. Integrations should read `allowance`.

## Deployment and operational responsibilities

Deploy the creation bytecode for `SwornBySwarm` with no appended arguments and
no ETH. The artifact is `out/SwornBySwarm.sol/SwornBySwarm.json`. The constructor
does not call any external contract and works on an otherwise empty chain.
When deployed through a factory, **the factory receives all tokens**, not the
transaction sender or a separately named owner. No signer or address needs to
be embedded in this repository.

The IMD launch infrastructure is responsible for deployment and the subsequent
allocation: 10% to its MerkleDistributor, 80% toward pool seeding, and the remaining
10% to the requester's supplied remainder recipient. Those actions belong to
the factory; the token does not reserve or distribute balances itself. Pool
configuration, economics, and `launch.json` belong to the separate manifest and
launch steps. No application contracts are needed for this token.

After launch, the operator should verify the deployed source and compiler
settings, metadata, supply, and factory allocation receipts. There are no
owner settings or recurring administrative transactions. Holders control their
transfers and allowances. Use limited approvals where practical; when replacing
a nonzero allowance, revoke it first and confirm the transaction before granting
the replacement to reduce the standard ERC-20 allowance-change race.

There is no rescue function. Tokens sent to this token's address, or to another
contract unable to return them, may be unrecoverable. Ordinary ETH sends revert;
ETH forced into the contract cannot be recovered. The token provides no price,
liquidity, or recovery guarantees.

## Build and validation

Foundry and Solidity 0.8.26 are prerequisites. All Solidity dependencies are
vendored as ordinary files under `lib/`; no dependency install, network access,
submodule, environment secret, FFI, filesystem permission, or RPC is required
to build and test once that compiler is installed.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x63bf4fdca190d770233c09626fe8a7be0740f9e57f3ef31b313eae3117f68a9b forge test
forge fmt --check
```

The configuration runs 1,024 cases per fuzz test and 128 sequences of 64 calls
per invariant. Tests have independent setup and do not read or write environment
variables. The seed above is consumed by Foundry, not the contracts or tests.

`test/SwornBySwarm.t.sol` covers metadata, constructor mint logs, CREATE2 factory
receipt, exact transfers and events, approvals and revocation, finite and unlimited
allowances, self/zero transfers, invalid recipients, insufficient balances and
allowances, rollback, and the absence of common mint/burn/admin entry points.
It also models the launch allocation, claims, and token transfers into/out of a
pool address. This is a token-flow test, not a Uniswap integration test.

`test/SwornBySwarm.invariant.t.sol` exercises randomized transfers, approvals,
and delegated transfers among four actors. It checks a separate balance and
allowance ledger, failure atomicity, total supply, and conservation of all funds.
Unexpected handler reverts fail the campaign.

The supplied protected launch tests require the verifier's factory/pool fixtures
and manifest environment; they are not included as local runnable tests. The
independent verifier supplies that integration environment. Local build, tests,
and formatting are the validation performed here; Slither and Mythril have not
been run. Tests and source review do not replace the independent security review
required before release.

## Vendored dependencies

- OpenZeppelin Contracts **v5.0.2**: the five files needed by ERC-20 and its MIT license.
- Forge Standard Library **v1.9.7**: test utilities and MIT/Apache-2.0 licenses.

Each dependency directory includes `VENDORED.md` with its upstream tag and archive
digest, and `SHA256SUMS` for the unmodified selected source and license files.
