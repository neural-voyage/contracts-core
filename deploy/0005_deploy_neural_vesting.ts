import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import config from './config';

const deployNeuralVesting: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, ethers } = hre;
  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();

  await deploy('NeuralVesting', {
    from: deployer.address,
    args: [],
    log: true,
    waitConfirmations: 1
  });
};

export default deployNeuralVesting;
deployNeuralVesting.tags = ['deployNeuralVesting'];
deployNeuralVesting.dependencies = ['deployNeural'];
