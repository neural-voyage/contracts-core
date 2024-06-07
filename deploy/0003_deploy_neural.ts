import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const deployNeural: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, ethers } = hre;
  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();

  await deploy('Neural', {
    from: deployer.address,
    args: [],
    log: true,
    waitConfirmations: 1
  });

  const neural = (await ethers.getContract(
    'Neural',
    deployer
  ));
  const neuralFeeHandler = (await ethers.getContract(
    'NeuralFeeHandler',
    deployer
  ));
  await (await neuralFeeHandler.setNeural(neural.address)).wait();
};

export default deployNeural;
deployNeural.tags = ['deployNeural'];
deployNeural.dependencies = ['deployNeuralFeeHandler'];
