import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const deployVoyage: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, ethers } = hre;
  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();

  await deploy('Voyage', {
    from: deployer.address,
    args: [],
    log: true,
    waitConfirmations: 1,
  });

  const voyage = await ethers.getContract('Voyage', deployer);
  const voyageFeeHandler = await ethers.getContract(
    'VoyageFeeHandler',
    deployer
  );
  await (await voyageFeeHandler.setVoyage(voyage.address)).wait();
};

export default deployVoyage;
deployVoyage.tags = ['deployVoyage'];
deployVoyage.dependencies = ['deployVoyageFeeHandler'];
