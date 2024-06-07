import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import config from './config';

const deployNeuralFeeHandler: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, ethers } = hre;
  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();

  await deploy('NeuralFeeHandler', {
    from: deployer.address,
    args: [config.oracle, config.stakingFund, config.treasury],
    log: true,
    waitConfirmations: 1
  });
};

export default deployNeuralFeeHandler;
deployNeuralFeeHandler.tags = ['deployNeuralFeeHandler'];
deployNeuralFeeHandler.dependencies = [];
