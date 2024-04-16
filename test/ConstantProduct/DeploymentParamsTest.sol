// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Utils} from "test/libraries/Utils.sol";

import {ConstantProductTestHarness, ConstantProduct, IERC20} from "./ConstantProductTestHarness.sol";

abstract contract DeploymentParamsTest is ConstantProductTestHarness {
    function testSetsDeploymentParameters() public {
        require(address(solutionSettler) != address(0), "test should use a nonzero address");
        IERC20 token0 = IERC20(Utils.addressFromString("DeploymentParamsTest: any token0"));
        IERC20 token1 = IERC20(Utils.addressFromString("DeploymentParamsTest: any token1"));
        mockSafeApprove(token0, expectedDeploymentAddress(), solutionSettler.vaultRelayer());
        mockSafeApprove(token1, expectedDeploymentAddress(), solutionSettler.vaultRelayer());
        mockSafeApprove(token0, expectedDeploymentAddress(), defaultDeployer());
        mockSafeApprove(token1, expectedDeploymentAddress(), defaultDeployer());
        vm.prank(defaultDeployer());
        ConstantProduct constantProduct = new ConstantProduct(solutionSettler, token0, token1);
        assertEq(address(constantProduct.solutionSettler()), address(solutionSettler));
        assertEq(constantProduct.solutionSettlerDomainSeparator(), solutionSettler.domainSeparator());
        assertEq(address(constantProduct.token0()), address(token0));
        assertEq(address(constantProduct.token1()), address(token1));
    }

    function approvedToken(string memory name) private returns (IERC20 token) {
        token = IERC20(Utils.addressFromString(name));
        mockSafeApprove(token, expectedDeploymentAddress(), solutionSettler.vaultRelayer());
        mockSafeApprove(token, expectedDeploymentAddress(), defaultDeployer());
        vm.mockCallRevert(address(token), hex"", abi.encode("Unexpected call to token contract"));
    }

    function revertingToken(string memory name, address spenderGoodApproval, address spenderBadApproval)
        private
        returns (IERC20 token)
    {
        token = IERC20(Utils.addressFromString(name));
        mockSafeApprove(token, expectedDeploymentAddress(), spenderGoodApproval);
        mockZeroAllowance(token, expectedDeploymentAddress(), spenderBadApproval);
        vm.mockCallRevert(
            address(token),
            abi.encodeCall(IERC20.approve, (spenderBadApproval, type(uint256).max)),
            "`approve` is an expected call"
        );
        vm.mockCallRevert(address(token), hex"", abi.encode("Unexpected call to token contract"));
    }

    function revertApproveVaultRelayerToken(string memory name) private returns (IERC20) {
        return revertingToken(name, defaultDeployer(), solutionSettler.vaultRelayer());
    }

    function revertApproveDeployerToken(string memory name) private returns (IERC20) {
        return revertingToken(name, solutionSettler.vaultRelayer(), defaultDeployer());
    }

    function testDeploymentAllowsVaultRelayerToken0() public {
        IERC20 reverting = revertApproveVaultRelayerToken("reverting");
        IERC20 regular = approvedToken("regular");
        vm.expectRevert("`approve` is an expected call");
        vm.prank(defaultDeployer());
        new ConstantProduct(solutionSettler, reverting, regular);
    }

    function testDeploymentAllowsVaultRelayerToken1() public {
        IERC20 reverting = revertApproveVaultRelayerToken("reverting");
        IERC20 regular = approvedToken("regular");
        vm.expectRevert("`approve` is an expected call");
        vm.prank(defaultDeployer());
        new ConstantProduct(solutionSettler, regular, reverting);
    }

    function testDeploymentAllowsDeployerToken0() public {
        IERC20 reverting = revertApproveDeployerToken("reverting");
        IERC20 regular = approvedToken("regular");
        vm.expectRevert("`approve` is an expected call");
        vm.prank(defaultDeployer());
        new ConstantProduct(solutionSettler, reverting, regular);
    }

    function testDeploymentAllowsDeployerToken1() public {
        IERC20 reverting = revertApproveDeployerToken("reverting");
        IERC20 regular = approvedToken("regular");
        vm.expectRevert("`approve` is an expected call");
        vm.prank(defaultDeployer());
        new ConstantProduct(solutionSettler, regular, reverting);
    }

    function testDeploymentRevertsIfApprovalReturnsFalse() public {
        IERC20 regular = approvedToken("regular");
        IERC20 falseOnApproval = IERC20(Utils.addressFromString("this token returns false on approval"));
        mockSafeApprove(falseOnApproval, expectedDeploymentAddress(), solutionSettler.vaultRelayer());
        mockZeroAllowance(falseOnApproval, expectedDeploymentAddress(), defaultDeployer());
        vm.mockCall(
            address(falseOnApproval),
            abi.encodeCall(IERC20.approve, (defaultDeployer(), type(uint256).max)),
            abi.encode(false)
        );

        vm.prank(defaultDeployer());
        vm.expectRevert("SafeERC20: ERC20 operation did not succeed");
        new ConstantProduct(solutionSettler, falseOnApproval, regular);
    }

    function testDeploymentSucceedsIfApproveReturnsNoData() public {
        IERC20 regular = approvedToken("regular");
        IERC20 noDataApproval = IERC20(Utils.addressFromString("this token returns false on approval"));
        mockSafeApprove(noDataApproval, expectedDeploymentAddress(), solutionSettler.vaultRelayer());
        mockZeroAllowance(noDataApproval, expectedDeploymentAddress(), defaultDeployer());
        vm.mockCall(
            address(noDataApproval),
            abi.encodeCall(IERC20.approve, (defaultDeployer(), type(uint256).max)),
            abi.encode()
        );

        vm.prank(defaultDeployer());
        new ConstantProduct(solutionSettler, noDataApproval, regular);
    }

    function defaultDeployer() private pure returns (address) {
        return Utils.addressFromString("DeploymentParamsTest: deployer");
    }

    function expectedDeploymentAddress() private pure returns (address) {
        return vm.computeCreateAddress(defaultDeployer(), 0);
    }
}
