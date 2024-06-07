import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import config from './config';

const deployNeuralStaking: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, ethers } = hre;
  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();

  const neural = (await ethers.getContract(
    'Neural',
    deployer
  ));
  const operatingSystem = (await ethers.getContract(
    'OperatingSystem',
    deployer
  ));
  await deploy('NeuralTokenStaking', {
    from: deployer.address,
    args: [
      neural.address,
      operatingSystem.address,
      ethers.utils.parseEther('20000000'), // totalRewards = 20M
      0, // minimumDeposit
      80, // apr1Month
      120, // apr3Month
      200, // apr6Month
      365, // apr12Month
    ],
    log: true,
    waitConfirmations: 1
  });
  const neuralTokenStaking = (await ethers.getContract(
    'NeuralTokenStaking',
    deployer
  ));

  await (await operatingSystem.updateWhitelist(neuralTokenStaking.address, true)).wait();

  await (await neural.approve(neuralTokenStaking.address, ethers.utils.parseEther('20000000')));
  await (await neuralTokenStaking.initialize()).await();

  await (await neuralTokenStaking.enableDepositing()).wait();
};

export default deployNeuralStaking;
deployNeuralStaking.tags = ['deployNeuralStaking'];
deployNeuralStaking.dependencies = ['deployNeural', 'deployOperatingSystem'];
