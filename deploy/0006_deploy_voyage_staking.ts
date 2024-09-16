import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import config from './config';

const deployVoyageStaking: DeployFunction = async (
  hre: HardhatRuntimeEnvironment
) => {
  const { deployments, ethers } = hre;
  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();

  const voyage = await ethers.getContract('Voyage', deployer);
  const operatingSystem = await ethers.getContract('OperatingSystem', deployer);
  await deploy('VoyageTokenStaking', {
    from: deployer.address,
    args: [
      voyage.address,
      operatingSystem.address,
      ethers.utils.parseEther('20000000'), // totalRewards = 20M
      0, // minimumDeposit
      80, // apr1Month
      120, // apr3Month
      200, // apr6Month
      365, // apr12Month
    ],
    log: true,
    waitConfirmations: 1,
  });
  const voyageTokenStaking = await ethers.getContract(
    'VoyageTokenStaking',
    deployer
  );

  await (
    await operatingSystem.updateWhitelist(voyageTokenStaking.address, true)
  ).wait();

  await await voyage.approve(
    voyageTokenStaking.address,
    ethers.utils.parseEther('20000000')
  );
  await (await voyageTokenStaking.initialize()).await();

  await (await voyageTokenStaking.enableDepositing()).wait();
};

export default deployVoyageStaking;
deployVoyageStaking.tags = ['deployVoyageStaking'];
deployVoyageStaking.dependencies = ['deployVoyage', 'deployOperatingSystem'];
