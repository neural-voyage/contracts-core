import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import config from './config';

const deployVoyageVesting: DeployFunction = async (
  hre: HardhatRuntimeEnvironment
) => {
  const { deployments, ethers } = hre;
  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();

  await deploy('VoyageVesting', {
    from: deployer.address,
    args: [],
    log: true,
    waitConfirmations: 1,
  });
};

export default deployVoyageVesting;
deployVoyageVesting.tags = ['deployVoyageVesting'];
deployVoyageVesting.dependencies = ['deployVoyage'];
