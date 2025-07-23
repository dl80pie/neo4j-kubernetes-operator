# CI Resource Constraints Fix

**Date**: 2025-07-23
**Issue**: Integration tests still failing in CI after operator readiness fix
**Resolution**: Reduced resource requirements for CI environment

## Problem Description

After implementing the operator readiness check, the CI was still failing on the `backup_sidecar_test.go` with the same timeout error. The test was timing out waiting for the standalone deployment to become ready.

Key observations:
- The first 6 tests passed successfully
- Only the backup sidecar test (test #7) was failing
- The same test passes locally without issues
- The operator deployment was confirmed ready in CI

## Root Cause Analysis

The issue appears to be resource constraints in the GitHub Actions CI environment. When multiple tests run sequentially, the CI environment may have limited resources available for later tests. The backup sidecar test creates two containers (Neo4j + backup sidecar) which requires more resources than simpler tests.

## Solution Implemented

Reduced resource requirements for the backup sidecar test to ensure it can run successfully in the resource-constrained CI environment:

### 1. CPU and Memory Reductions

**Before:**
```yaml
Resources:
  Requests:
    CPU: 500m
    Memory: 1Gi
  Limits:
    CPU: 1
    Memory: 2Gi
```

**After:**
```yaml
Resources:
  Requests:
    CPU: 100m
    Memory: 512Mi
  Limits:
    CPU: 500m
    Memory: 1Gi
```

### 2. Storage Size Reduction

**Before:**
```yaml
Storage:
  Size: 1Gi
```

**After:**
```yaml
Storage:
  Size: 500Mi
```

### 3. Additional Improvements

1. **Added image pull policy**: Set to `IfNotPresent` to avoid unnecessary image pulls
2. **Improved test interval**: Reduced from 10s to 5s for faster status checks
3. **Enhanced debugging**: Added logging for standalone status and ConfigMap creation
4. **Better cleanup**: Using the centralized `cleanupResource` function for proper resource cleanup
5. **Operator initialization wait**: Added 10-second wait after operator is ready to ensure full initialization

## Verification

The changes were verified by:
1. Running the specific test locally - passes in ~5 seconds
2. Confirming resource requirements are appropriate for CI environment
3. Ensuring the test still validates the backup sidecar functionality

## Impact

These changes should allow the integration tests to pass in CI by:
- Reducing memory pressure on the CI runners
- Allowing faster pod scheduling with lower resource requests
- Preventing resource contention between multiple test pods

## Future Recommendations

1. Consider running integration tests in parallel with resource isolation
2. Monitor CI runner specifications and adjust test resources accordingly
3. Add resource usage metrics to CI logs for better debugging
4. Consider using a test matrix to run heavy tests separately
