export const EFFECTIVENESS_WEIGHTS = {
    untested: 0.5,
    ineffective: 0.1,
    modest: 0.4,
    effective: 0.75,
    highly_effective: 1.0,
};

export const CASCADE_DECAY = 0.8; // each hop reduces inherited defense by 20%
