const ethers = require('ethers');

const abiCoder = new ethers.utils.AbiCoder();
const encodedArgs = abiCoder.encode(
  ['address', 'address', 'address', 'address', 'uint256', 'uint256', 'address', 'address', 'address'],
  [
    '0x0000000000000000000000000000000000000000',
    '0x9cA9D67f613c50741E30e5Ef88418891e254604d',
    '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',
    '0x0fBcbaEA96Ce0cF7Ee00A8c19c3ab6f5Dc8E1921',
    30184,
    30110,
    '0x1a44076050125825900e736c501f859c50fE728c',
    '0x03773f85756acaC65A869e89E3B7b2fcDA6Be140',
    '0xeEbe5E1bD522BbD9a64f28d923c0680F89DB5c59'
  ]
);

console.log(encodedArgs);