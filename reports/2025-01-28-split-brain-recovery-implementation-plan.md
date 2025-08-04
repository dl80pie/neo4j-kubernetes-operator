# Split-brain Recovery Implementation Plan

**Date**: 2025-01-28
**Feature**: Automatic Split-brain Detection and Recovery
**Priority**: Critical
**Estimated Timeline**: 6 weeks

## Executive Summary

This document outlines the implementation plan for automatic split-brain detection and recovery in the Neo4j Kubernetes Operator. Split-brain scenarios occur when network partitions cause a cluster to split into multiple sub-clusters, each believing it has quorum. This feature will provide automatic detection within 30 seconds and configurable recovery strategies to maintain data integrity and service availability.

## Problem Statement

### Current State
- Neo4j Enterprise clusters use V2_ONLY discovery mode
- Basic health checks exist but no split-brain detection
- No automatic recovery mechanisms
- Manual intervention required for split-brain scenarios
- Risk of data inconsistency and service unavailability

### Business Impact
- **Downtime**: Hours of manual intervention required
- **Data Risk**: Potential for data inconsistency
- **Operational Burden**: 24/7 on-call requirement
- **SLA Impact**: Unable to meet 99.99% availability targets

## Technical Design

### Architecture Overview

```
┌─────────────────────────────────────────────┐
│         Neo4j Operator Controller           │
├─────────────────────────────────────────────┤
│                                             │
│  ┌─────────────────┐  ┌─────────────────┐  │
│  │  Split-brain    │  │    Recovery     │  │
│  │   Detector      │  │   Orchestrator  │  │
│  └────────┬────────┘  └────────┬────────┘  │
│           │                     │           │
│  ┌────────▼────────────────────▼────────┐  │
│  │         State Machine                 │  │
│  │  ┌─────────┐  ┌─────────┐  ┌──────┐ │  │
│  │  │Detecting│─▶│Recovery │─▶│Stable│ │  │
│  │  └─────────┘  └─────────┘  └──────┘ │  │
│  └───────────────────────────────────────┘  │
│                                             │
│  ┌─────────────────┐  ┌─────────────────┐  │
│  │  Neo4j Client   │  │  Metrics/Events │  │
│  │   (Bolt)        │  │   Publisher     │  │
│  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────┘
```

### Core Components

#### 1. Split-brain Detector (`internal/controller/splitbrain_detector.go`)
```go
type SplitBrainDetector struct {
    client      neo4j.Client
    interval    time.Duration
    threshold   int

    // Detection algorithm
    detectPartitions() ([]ClusterPartition, error)
    analyzeTopology() (*TopologyState, error)
    compareNodeViews() (bool, error)
}
```

#### 2. Recovery Orchestrator (`internal/controller/splitbrain_recovery.go`)
```go
type RecoveryOrchestrator struct {
    strategy    RecoveryStrategy
    executor    *RecoveryExecutor
    validator   *RecoveryValidator

    // Recovery strategies
    executeMinorityShutdown() error
    executeLeaderPreference() error
    executeManualIntervention() error
}
```

#### 3. CRD Extensions
```yaml
apiVersion: neo4j.neo4j.com/v1alpha1
kind: Neo4jEnterpriseCluster
spec:
  splitBrainRecovery:
    enabled: true
    detectionInterval: "30s"
    strategy: "leader-preference"
    leaderPreference:
      preferredNodes:
        - zone: "us-east-1a"
          weight: 100
        - zone: "us-east-1b"
          weight: 50
      minimumQuorum: 3
    notifications:
      slack:
        webhookSecret: "slack-webhook"
      email:
        recipients:
          - "oncall@company.com"
```

### Detection Algorithm

```python
# Pseudo-code for split-brain detection
def detect_split_brain():
    topology = {}

    # Query each node's view of the cluster
    for node in cluster.nodes:
        try:
            node_view = query_node_topology(node)
            topology[node.id] = node_view
        except:
            topology[node.id] = None

    # Analyze topology views
    partitions = []
    analyzed = set()

    for node_id, view in topology.items():
        if node_id in analyzed or view is None:
            continue

        partition = {node_id}
        for other_id, other_view in topology.items():
            if views_match(view, other_view):
                partition.add(other_id)
                analyzed.add(other_id)

        partitions.append(partition)

    # Detect split-brain condition
    if len(partitions) > 1:
        return True, partitions

    return False, []
```

### Recovery Strategies

#### 1. Minority Shutdown
- Identify the partition with majority of nodes
- Gracefully shutdown nodes in minority partitions
- Suitable for: Simple deployments with clear majority

#### 2. Leader Preference
- Use predefined node preferences and weights
- Promote preferred nodes as leaders
- Shutdown non-preferred partitions
- Suitable for: Multi-zone deployments with zone preferences

#### 3. Manual Intervention
- Alert operators and pause automated actions
- Provide detailed partition information
- Wait for manual resolution
- Suitable for: Critical data scenarios requiring human judgment

## Implementation Plan

### Phase 1: Detection Infrastructure (Week 1-2)

#### Week 1
- [ ] Create `SplitBrainDetector` component
- [ ] Implement topology query methods
- [ ] Add cluster membership comparison logic
- [ ] Create detection state machine

#### Week 2
- [ ] Integrate detector into reconciliation loop
- [ ] Add detection metrics and events
- [ ] Implement detection interval configuration
- [ ] Create unit tests for detection logic

### Phase 2: Recovery Mechanisms (Week 3-4)

#### Week 3
- [ ] Implement `RecoveryOrchestrator` component
- [ ] Create minority shutdown strategy
- [ ] Add safety checks and validation
- [ ] Implement recovery state tracking

#### Week 4
- [ ] Implement leader preference strategy
- [ ] Add manual intervention workflow
- [ ] Create recovery audit logging
- [ ] Add notification integrations

### Phase 3: Integration and Safety (Week 5-6)

#### Week 5
- [ ] Integrate with existing controller
- [ ] Add comprehensive validation
- [ ] Implement rollback mechanisms
- [ ] Create integration tests

#### Week 6
- [ ] End-to-end testing
- [ ] Chaos testing with network partitions
- [ ] Performance impact assessment
- [ ] Documentation and runbooks

## Testing Strategy

### Unit Tests
```go
func TestSplitBrainDetection(t *testing.T) {
    // Test cases:
    // - Normal cluster state (no split-brain)
    // - Two-way partition
    // - Three-way partition
    // - Partial connectivity
    // - Node failures vs partition
}

func TestRecoveryStrategies(t *testing.T) {
    // Test cases:
    // - Minority shutdown with clear majority
    // - Leader preference with zone failures
    // - Edge cases (equal partitions)
    // - Recovery validation
}
```

### Integration Tests
```go
var _ = Describe("Split-brain Recovery", func() {
    It("should detect split-brain within 30 seconds", func() {
        // Create cluster
        // Induce network partition
        // Verify detection time
        // Verify partition identification
    })

    It("should recover using minority shutdown", func() {
        // Create split-brain scenario
        // Configure minority shutdown
        // Verify correct nodes shutdown
        // Verify cluster reformation
    })
})
```

### Chaos Tests
- Network partition injection using Chaos Mesh
- Clock skew scenarios
- Partial connectivity (asymmetric partitions)
- Recovery under load
- Cascading failure prevention

## Risk Analysis

### Technical Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| False positive detection | High | Medium | Multiple detection cycles, configurable thresholds |
| Data loss during recovery | Critical | Low | Read-only mode before shutdown, data validation |
| Recovery causing cascading failures | High | Low | Circuit breaker pattern, gradual recovery |
| Detection performance impact | Medium | Medium | Async detection, caching, rate limiting |

### Operational Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Operator confusion | Medium | High | Comprehensive documentation, clear events |
| Conflict with manual actions | High | Medium | Manual override capability, operation locking |
| Alert fatigue | Medium | Medium | Smart notification grouping, severity levels |

## Success Metrics

### Performance Metrics
- **Detection Time**: P99 < 30 seconds
- **Recovery Time**: P99 < 2 minutes
- **False Positive Rate**: < 0.1%
- **Recovery Success Rate**: > 99%

### Business Metrics
- **MTTR Reduction**: From hours to minutes
- **Data Loss**: Zero during automated recovery
- **Operational Burden**: 80% reduction in manual interventions
- **Availability**: Contribute to 99.99% SLA

## Configuration Examples

### Basic Configuration
```yaml
spec:
  splitBrainRecovery:
    enabled: true
    strategy: "minority-shutdown"
```

### Advanced Multi-Zone Configuration
```yaml
spec:
  splitBrainRecovery:
    enabled: true
    detectionInterval: "20s"
    strategy: "leader-preference"
    leaderPreference:
      preferredNodes:
        - zone: "us-east-1a"
          weight: 100
        - zone: "us-east-1b"
          weight: 80
        - zone: "us-east-1c"
          weight: 60
      minimumQuorum: 3
      tieBreaker:
        mode: "node-age"  # oldest node wins
    notifications:
      slack:
        webhookSecret: "ops-slack-webhook"
        channel: "#neo4j-alerts"
        severity: "critical"
      pagerduty:
        integrationKey: "pagerduty-key"
```

## Rollout Plan

### Phase 1: Beta Testing (Week 7-8)
- Deploy to staging environments
- Monitor detection accuracy
- Gather feedback from early adopters
- Refine detection thresholds

### Phase 2: Production Rollout (Week 9-10)
- Start with non-critical clusters
- Enable detection-only mode
- Gradually enable recovery
- Monitor metrics and alerts

### Phase 3: General Availability (Week 11-12)
- Full documentation release
- Training materials
- Support team enablement
- Feature promotion

## Dependencies

### External Dependencies
- Neo4j 5.26+ with V2_ONLY discovery
- Kubernetes 1.25+ for advanced networking APIs
- Cert-manager for TLS (if TLS enabled)

### Internal Dependencies
- Neo4j Bolt client enhancements
- Metrics subsystem updates
- Event recording framework

## Future Enhancements

### Short Term (3-6 months)
- Machine learning for detection optimization
- Predictive split-brain prevention
- Integration with service mesh

### Long Term (6-12 months)
- Multi-region split-brain handling
- Automated data reconciliation
- Self-healing network configuration

## Conclusion

The split-brain recovery feature addresses a critical operational challenge in running Neo4j clusters on Kubernetes. By providing automatic detection and configurable recovery strategies, we can significantly reduce downtime, prevent data loss, and lower operational burden. The phased implementation approach ensures thorough testing and safe rollout while delivering value incrementally.

The success of this feature will be measured by reduced MTTR, zero data loss during recovery, and improved cluster availability, contributing directly to achieving 99.99% SLA targets for enterprise deployments.
