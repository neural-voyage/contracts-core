import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import config from './config';

const deployCurveIntegrationPwrd3Crv: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, ethers } = hre;
  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();

  const neuralFeeHandler = (await ethers.getContract(
    'NeuralFeeHandler',
    deployer
  ));

  await deploy('CurveIntegrationPwrd3Crv', {
    contract: "NeuralPWRD3CRVIntegration",
    from: deployer.address,
    args: [config.oracle, neuralFeeHandler.address],
    log: true,
    waitConfirmations: 1
  });

  const curveIntegrationFrax3Crv = (await ethers.getContract('CurveIntegrationFrax3Crv', deployer));
  await (await curveIntegrationFrax3Crv.enableDepositing()).wait();
};

export default deployCurveIntegrationPwrd3Crv;
deployCurveIntegrationPwrd3Crv.tags = ['deployCurveIntegrationPwrd3Crv'];
deployCurveIntegrationPwrd3Crv.dependencies = ['deployNeuralFeeHandler'];
