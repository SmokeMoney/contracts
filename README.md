## Smoke Money Contracts

### Prerequisites

- Foundry
- Node.js

### Setup

```bash
npm install
forge build
```
### Temporary Fix

Change the `TestHelperOz5.sol` file in the `node_modules` folder to the one in the `contracts` folder.

```bash
import { Test } from "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
```
