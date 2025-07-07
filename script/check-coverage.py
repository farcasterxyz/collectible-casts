#!/usr/bin/env python3

import subprocess
import re
import sys

# ANSI color codes
RED = '\033[0;31m'
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
NC = '\033[0m'  # No Color

# Production contracts to check (excluding test helpers and mocks)
PRODUCTION_CONTRACTS = [
    "src/CollectibleCast.sol",
    "src/Metadata.sol",
    "src/Minter.sol",
    "src/TransferValidator.sol",
    "src/Auction.sol"
]

def main():
    print("🔍 Checking test coverage for production contracts...")
    
    # Run forge coverage
    try:
        result = subprocess.run(
            ["forge", "coverage", "--report", "summary"],
            capture_output=True,
            text=True,
            check=True
        )
        coverage_output = result.stdout
    except subprocess.CalledProcessError as e:
        print(f"{RED}❌ Coverage check failed to run{NC}")
        print(e.stderr)
        sys.exit(1)
    
    # Parse coverage data
    coverage_data = {}
    lines = coverage_output.split('\n')
    
    for line in lines:
        if line.startswith('|') and ' | ' in line:
            parts = line.split('|')
            if len(parts) >= 6:
                contract = parts[1].strip()
                if contract and not contract.startswith('-'):
                    # Extract percentages from format "100.00% (12/12)"
                    lines_match = re.search(r'(\d+\.\d+)%', parts[2])
                    statements_match = re.search(r'(\d+\.\d+)%', parts[3])
                    branches_match = re.search(r'(\d+\.\d+)%', parts[4])
                    functions_match = re.search(r'(\d+\.\d+)%', parts[5])
                    
                    coverage_data[contract] = {
                        'lines': float(lines_match.group(1)) if lines_match else 0,
                        'statements': float(statements_match.group(1)) if statements_match else 0,
                        'branches': float(branches_match.group(1)) if branches_match else 0,
                        'functions': float(functions_match.group(1)) if functions_match else 0
                    }
    
    # Check coverage for production contracts
    print("\n📊 Coverage Report:")
    print("====================")
    
    all_pass = True
    contracts_checked = []
    
    for contract in PRODUCTION_CONTRACTS:
        if contract in coverage_data:
            contracts_checked.append(contract)
            print(f"\n📄 {contract}:")
            data = coverage_data[contract]
            
            for metric, value in data.items():
                if value == 100.0:
                    print(f"  ✅ {metric.capitalize()}: {GREEN}{value:.2f}%{NC}")
                else:
                    print(f"  ❌ {metric.capitalize()}: {RED}{value:.2f}%{NC} (must be 100%)")
                    all_pass = False
    
    # Show other contracts found
    print("\n====================")
    print("\n📋 All source contracts:")
    
    for contract in sorted(coverage_data.keys()):
        if contract.startswith('src/') and contract != 'src/Counter.sol':
            if contract not in PRODUCTION_CONTRACTS:
                print(f"  ⚠️  {YELLOW}{contract} (not tracked){NC}")
            elif contract in contracts_checked:
                data = coverage_data[contract]
                all_100 = all(v == 100.0 for v in data.values())
                status = "✅" if all_100 else "❌"
                print(f"  {status} {contract}")
    
    print("\n====================")
    
    # Final result
    if not all_pass:
        print(f"{RED}❌ Coverage check failed!{NC}")
        print(f"{YELLOW}All production contracts must have 100% test coverage.{NC}")
        sys.exit(1)
    else:
        print(f"{GREEN}✅ All production contracts have 100% test coverage!{NC}")
        sys.exit(0)

if __name__ == "__main__":
    main()