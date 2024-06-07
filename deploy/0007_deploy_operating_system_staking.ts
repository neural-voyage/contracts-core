import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import config from './config';

const deployOperatingSystemStaking: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, ethers } = hre;
  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();

  const operatingSystem = (await ethers.getContract(
    'OperatingSystem',
    deployer
  ));
  await deploy('OperatingSystemStaking', {
    from: deployer.address,
    args: [config.oracle, operatingSystem.address, config.stakingFund],
    log: true,
    waitConfirmations: 1
  });
  const operatingSystemStaking = (await ethers.getContract(
    'OperatingSystemStaking',
    deployer
  ));
  await (await operatingSystemStaking.setMinimumDistribution(10000000)).wait();
  await (await operatingSystem.updateWhitelist(operatingSystemStaking.address, true)).wait();
  await (await operatingSystemStaking.enableDepositing()).wait();
};

export default deployOperatingSystemStaking;
deployOperatingSystemStaking.tags = ['deployOperatingSystemStaking'];
deployOperatingSystemStaking.dependencies = ['deployOperatingSystem'];
