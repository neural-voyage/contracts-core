import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import config from './config';

const deployCurveIntegrationMin3Crv: DeployFunction = async (
  hre: HardhatRuntimeEnvironment
) => {
  const { deployments, ethers } = hre;
  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();

  const voyageFeeHandler = await ethers.getContract(
    'VoyageFeeHandler',
    deployer
  );

  await deploy('CurveIntegrationMim3Crv', {
    contract: 'VoyageMIM3CRVIntegration',
    from: deployer.address,
    args: [config.oracle, voyageFeeHandler.address],
    log: true,
    waitConfirmations: 1,
  });

  const curveIntegrationFrax3Crv = await ethers.getContract(
    'CurveIntegrationFrax3Crv',
    deployer
  );
  await (await curveIntegrationFrax3Crv.enableDepositing()).wait();
};

export default deployCurveIntegrationMin3Crv;
deployCurveIntegrationMin3Crv.tags = ['deployCurveIntegrationMin3Crv'];
deployCurveIntegrationMin3Crv.dependencies = ['deployVoyageFeeHandler'];
