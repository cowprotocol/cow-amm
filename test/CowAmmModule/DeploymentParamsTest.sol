// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {CowAmmModuleTestHarness, CowAmmModule} from "./CowAmmModuleTestHarness.sol";

abstract contract DeploymentParamsTest is CowAmmModuleTestHarness {
    function testSetsSolutionSettler() public {
        require(address(settlement) != address(0), "test should use a nonzero address");
        require(address(eHandler) != address(0), "test should use a nonzero address");
        require(address(composableCow) != address(0), "test should use a nonzero address");
        require(address(constantProduct) != address(0), "test should use a nonzero address");
        require(address(token0) != address(0), "test should use a nonzero address");
        require(address(token1) != address(0), "test should use a nonzero address");

        CowAmmModule cowAmmModule =
            new CowAmmModule(settlement, eHandler, composableCow, constantProduct, token0, token1);

        assertEq(address(cowAmmModule.SETTLER()), address(settlement));
        assertEq(address(cowAmmModule.EXTENSIBLE_FALLBACK_HANDLER()), address(eHandler));
        assertEq(address(cowAmmModule.COMPOSABLE_COW()), address(composableCow));
        assertEq(address(cowAmmModule.HANDLER()), address(constantProduct));
        assertEq(address(cowAmmModule.VAULT_RELAYER()), address(settlement.vaultRelayer()));
        assertEq(cowAmmModule.COW_DOMAIN_SEPARATOR(), settlement.domainSeparator());
        assertEq(address(cowAmmModule.token0()), address(token0));
        assertEq(address(cowAmmModule.token1()), address(token1));
    }
}
