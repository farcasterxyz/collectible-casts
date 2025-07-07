# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Foundry-based Ethereum smart contract development project. Foundry is a Rust-based toolkit that provides a complete development environment for Solidity smart contracts.

- **Foundry Documentation**: https://getfoundry.sh/

### Project Documentation

- **[SPEC.md](./SPEC.md)** - Complete specification for the Collectible Casts system, including architecture, goals, and detailed contract requirements
- **[PLAN.md](./PLAN.md)** - High-level implementation plan outlining development phases and testing strategy
- **[TASKS.md](./TASKS.md)** - Detailed task breakdown with specific implementation steps and test scenarios

## Essential Commands

### Building and Testing

```bash
forge build              # Compile all contracts
forge build --sizes      # Compile and show contract sizes
forge test              # Run all tests
forge test -vvv         # Run tests with maximum verbosity (useful for debugging)
forge test --match-test testName  # Run specific test
forge test --match-contract ContractName  # Run tests for specific contract
forge test --gas-report  # Run tests with gas usage report

# Fuzz testing profiles
forge test                    # Default: 2048 fuzz runs
FOUNDRY_PROFILE=ci forge test # CI: 10,000 fuzz runs
FOUNDRY_PROFILE=deep forge test # Deep: 50,000 fuzz runs
forge test --fuzz-runs 100000 --fuzz-seed 0x123  # Custom deterministic deep fuzzing
```

### Code Quality

```bash
forge fmt               # Format all Solidity files (120 char line length)
forge fmt --check       # Check formatting without modifying files
forge snapshot          # Generate gas usage snapshots
forge snapshot --check  # Compare gas usage against .gas-snapshot
forge coverage          # Generate test coverage report (minimum 94%)
python3 script/check-coverage.py  # Verify 100% coverage for production contracts
```

### Local Development

```bash
anvil                   # Start local Ethereum node for testing
anvil --fork-url <RPC_URL>  # Fork mainnet for testing
```

### Deployment

```bash
forge script script/Counter.s.sol:CounterScript --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast
forge script script/Counter.s.sol:CounterScript --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast --verify
```

## CRITICAL: Test-Driven Development (TDD) Process

**This project STRICTLY follows TDD methodology. No production code should be written without a failing test first.**

### TDD Workflow - RED → GREEN → REFACTOR → COMMIT

1. **RED**: Write a failing test first

   ```bash
   # Write test in test/ContractName.t.sol
   forge test --match-test test_NewFeature -vvv  # See it fail
   ```

2. **GREEN**: Write minimal code to pass

   ```bash
   # Write just enough code in src/ContractName.sol
   forge test --match-test test_NewFeature  # See it pass
   ```

3. **REFACTOR**: Improve code while keeping tests green

   ```bash
   # Refactor implementation
   forge test  # Ensure all tests still pass
   forge fmt   # Format code
   ```

4. **COMMIT**: Only commit when all tests pass
   ```bash
   forge test            # Final test run
   forge coverage        # Check coverage
   python3 script/check-coverage.py  # Verify 100% coverage
   git add -A
   git commit -m "feat: implement feature with tests"
   ```

### TDD Rules

- **NEVER write production code without a failing test**
- **NEVER write more production code than needed to pass the test**
- **NEVER refactor with failing tests**
- **ALWAYS run tests before committing**
- **Target 100% test coverage** - use `forge coverage` to verify
- **Tests are first-class code** - apply the same quality standards to tests as production code
- **Prefer fuzz tests** - write fuzz tests for all functions that accept parameters

## Coding Standards and Conventions

### File Structure and Code Organization

- All Solidity files must include:
  ```solidity
  // SPDX-License-Identifier: UNLICENSED
  pragma solidity ^0.8.30;
  ```
- Import order (separated by blank lines):
  1. External dependencies (OpenZeppelin, forge-std)
  2. Interfaces
  3. Abstract contracts/libraries
  4. Relative imports
- Example:

  ```solidity
  import {ERC721} from "openzeppelin/contracts/token/ERC721/ERC721.sol";

  import {IIdRegistry} from "./interfaces/IIdRegistry.sol";

  import {Signatures} from "./abstract/Signatures.sol";
  ```

- Contract internal organization:
  1. Custom errors
  2. Events
  3. Constants
  4. State variables (grouped by visibility)
  5. Constructor
  6. Functions (external → public → internal → private)

### Naming Conventions

- **Contract files**: PascalCase (e.g., `TokenVault.sol`, `AccessManager.sol`)
- **Test files**: `ContractName.t.sol` (e.g., `TokenVault.t.sol`)
- **Script files**: `ContractName.s.sol` or descriptive names (e.g., `Deploy.s.sol`)
- **Test contracts**: `ContractNameTest` (e.g., `TokenVaultTest`)
- **Test functions**:
  - `test_FunctionName()` for unit tests
  - `testFuzz_FunctionName(uint256 param)` for fuzz tests
  - `testFail_FunctionName()` for tests expecting reverts
  - Use underscores in test function names for readability

### Error Handling

- **ALWAYS use custom errors instead of require statements**
  ```solidity
  // Bad
  require(msg.sender == owner, "Unauthorized");
  
  // Good
  error Unauthorized();
  if (msg.sender != owner) revert Unauthorized();
  ```
- Define custom errors at the contract level
- Include custom errors in interfaces so they can be imported
- Use descriptive error names that explain the failure condition

### Contract Development Patterns

- **Modular Architecture**: Each contract should have a single, well-defined purpose
- **Interface-First Design**: Define interfaces for all public contracts
- **Custom Errors**: Use custom errors instead of require statements
  ```solidity
  error Unauthorized();
  error InvalidSignature();
  error ExceedsMaximum(uint256 provided, uint256 maximum);
  ```
- **Events**: Emit events for all state changes with indexed parameters
- **Abstract Contracts**: Use for shared functionality (e.g., `Signatures`, `Nonces`, `EIP712`)
- **Access Control**: Implement role-based permissions where needed. Prefer simple Ownable if there are not multiple roles.
- **State Variables**: Group by visibility and document purpose
- **NatSpec Documentation**: Comprehensive documentation for all public functions
  ```solidity
  /**
   * @notice Registers a new ID for the caller
   * @param recovery The recovery address for this ID
   * @return fid The newly registered Farcaster ID
   */
  ```

### Testing Philosophy

**Tests are as important as production code.** Every test should be:

- **Clear**: Test names should describe what they test and expected behavior
- **Comprehensive**: Cover all possible scenarios and edge cases
- **Maintainable**: Well-structured and easy to update
- **Fast**: Optimize for quick feedback loops

### Testing Best Practices

- **Test-First Development**: Always write tests before implementation
- **One assertion per test**: Keep tests focused and clear
- **Descriptive test names**: `test_FunctionName_WhenCondition_ShouldExpectedBehavior()`
- **Test file structure**:

  ```solidity
  // SPDX-License-Identifier: UNLICENSED
  pragma solidity ^0.8.30;

  import {Test} from "forge-std/Test.sol";
  import {ContractName} from "../src/ContractName.sol";
  import {TestSuiteSetup} from "./TestSuiteSetup.sol";

  contract ContractNameTest is TestSuiteSetup {
      ContractName public contractInstance;

      function setUp() public override {
          super.setUp();
          contractInstance = new ContractName();
      }

      // Unit test
      function test_Deposit_WhenAmountIsValid_ShouldUpdateBalance() public {
          // Arrange
          uint256 amount = 100;

          // Act
          contractInstance.deposit(amount);

          // Assert
          assertEq(contractInstance.balance(), amount);
      }

      // Fuzz test (ALWAYS prefer when parameters exist)
      function testFuzz_Deposit_WhenAmountIsValid_ShouldUpdateBalance(uint256 amount) public {
          // Assume (set boundaries)
          amount = _bound(amount, 1, type(uint256).max);

          // Act
          contractInstance.deposit(amount);

          // Assert
          assertEq(contractInstance.balance(), amount);
      }
  }
  ```

### Comprehensive Test Coverage Requirements

Every function must have tests for:

1. **Happy path**: Normal expected usage
2. **Edge cases**: Boundary values (0, max values, etc.)
3. **Revert scenarios**: All possible failure modes
4. **State transitions**: Before/after state verification
5. **Events**: All emitted events with correct parameters
6. **Access control**: Permission and role-based tests
7. **Reentrancy**: Where applicable
8. **Gas optimization**: Track gas usage for critical functions

### Fuzz Testing Guidelines

- **Default to fuzz tests**: If a function takes parameters, write fuzz tests
- **Use `_bound()` over `vm.assume()`**: More efficient for constraining inputs
- **Standard fuzz runs**: 2,048 (default), 10,000 (CI profile), 50,000 (deep profile)
- **Test invariants**: Properties that should always hold true
- **Helper functions for fuzzing**:

  ```solidity
  function _assumeClean(address addr) internal pure {
      vm.assume(addr != address(0));
      vm.assume(addr.code.length == 0);
  }

  function _boundPk(uint256 pk) internal pure returns (uint256) {
      return _bound(pk, 1, type(uint256).max);
  }
  ```

- **Example fuzz test patterns**:

  ```solidity
  function testFuzz_Transfer_ShouldMaintainTotalSupply(
      address from,
      address to,
      uint256 amount
  ) public {
      // Assume valid addresses
      vm.assume(from != address(0) && to != address(0));
      vm.assume(from != to);

      // Setup
      uint256 totalSupply = token.totalSupply();
      deal(address(token), from, amount);

      // Act
      vm.prank(from);
      token.transfer(to, amount);

      // Assert invariant
      assertEq(token.totalSupply(), totalSupply);
  }
  ```

### Test Organization

- **Test Directories**: Organize tests by contract in dedicated directories
  ```
  test/
  ├── IdRegistry/
  │   ├── IdRegistry.t.sol
  │   └── IdRegistry.gas.t.sol
  ├── KeyRegistry/
  │   └── KeyRegistry.t.sol
  └── TestSuiteSetup.sol  # Base test contract
  ```
- **Base Test Contract**: Create `TestSuiteSetup.sol` for shared test utilities
- **Gas Snapshots**: Maintain `.gas-snapshot` files for gas optimization tracking

### Test Utilities and Helpers

- **Leverage forge-std utilities**:
  - `vm.prank()` for simulating different callers
  - `vm.expectRevert()` for testing reverts with custom errors
  - `vm.expectEmit()` for testing events (use all four checkTopic flags)
  - `vm.warp()` and `vm.roll()` for time/block manipulation
  - `_bound()` for constraining fuzz inputs efficiently
  - `deal()` for setting token balances
  - `hoax()` for pranking with ETH
  - `console2.log()` for debugging (remove before commit)
- **Common test helpers**:
  - `_assumeClean()` for validating addresses
  - `_boundPk()` for private key constraints
  - Mock contract creation helpers
- **Test modifiers**: For common preconditions

### Script Patterns

- Scripts should inherit from `Script` contract
- Use `vm.startBroadcast()` and `vm.stopBroadcast()` for deployment transactions
- Keep deployment logic modular and reusable
- Store deployment addresses and configuration appropriately

## Architecture

### Directory Structure

- `src/` - Production smart contracts
- `test/` - Test contracts (one test file per contract)
- `script/` - Deployment and interaction scripts
- `lib/` - External dependencies (git submodules)
- `out/` - Compiled artifacts (gitignored)
- `cache/` - Build cache (gitignored)
- `broadcast/` - Deployment logs (gitignored for development)

### Dependency Management

Dependencies are managed through git submodules in the `lib/` directory:

- `forge-std` - Foundry standard library for testing
- `openzeppelin-contracts` v5.1.0 - Industry-standard smart contract library
  - Documentation: https://docs.openzeppelin.com/contracts/5.x/
  - GitHub: https://github.com/OpenZeppelin/openzeppelin-contracts
  - Key contracts used:
    - `Ownable2Step` - Two-step ownership transfer for security
    - `ERC1155` - Multi-token standard implementation
- Add new dependencies with: `forge install owner/repo`
- Update dependencies with: `forge update`

### Environment Configuration

- Use `.env` files for environment-specific variables (never commit these)
- Load environment variables in scripts with `vm.envUint()`, `vm.envAddress()`, etc.
- Example `.env` structure:
  ```
  PRIVATE_KEY=0x...
  RPC_URL=https://...
  ETHERSCAN_API_KEY=...
  ```

### CI/CD and Quality Assurance

GitHub Actions workflow (.github/workflows/test.yml) should:

1. Check code formatting with `forge fmt --check`
2. Run solhint linting checks
3. Build contracts with `--sizes` flag
4. Run all tests with gas reporting
5. Generate and validate coverage (minimum 94%)
6. Compare gas snapshots

**Pre-commit hooks** (using `.lintstagedrc` or `.rusty-hook.toml`):

- Run `forge fmt --check` on staged `.sol` files
- Optionally run `solhint` for additional linting

**Foundry Profiles**:

- `default`: Development profile with 2,048 fuzz runs
- `ci`: CI profile with 10,000 fuzz runs for thorough testing
- `deep`: Deep testing profile with 50,000 fuzz runs for comprehensive edge case discovery

### Foundry Configuration

Recommended `foundry.toml` settings:

```toml
[profile.default]
solc_version = "0.8.30"
optimizer_runs = 100_000
fuzz = { runs = 2048 }
line_length = 120
tab_width = 4

[profile.ci]
fuzz = { runs = 10000 }

[profile.deep]
fuzz = { runs = 50000 }
```
