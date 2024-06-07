import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const deployOperatingSystem: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, ethers } = hre;
  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();

  await deploy('OperatingSystem', {
    from: deployer.address,
    args: [],
    log: true,
    waitConfirmations: 1
  });
};

export default deployOperatingSystem;
deployOperatingSystem.tags = ['deployOperatingSystem'];
deployOperatingSystem.dependencies = [];
