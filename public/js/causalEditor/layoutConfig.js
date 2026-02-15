export const NODE_TIERS = {
    // Col 1: Root Triggers & Background Factors
    HEALTH_ANXIETY: 1, OSA: 1, GENETICS: 1, SSRI: 1,
    // Col 2: Modifiable Inputs & Lifestyle
    STRESS: 2, SLEEP_DEP: 2,
    CAFFEINE: 2, ALCOHOL: 2, SMOKING: 2, AIRWAY_OBS: 2,
    // Col 3: Mediators / Disease States / Deficiencies
    CORTISOL: 3, CATECHOL: 3, GERD: 3, NEG_PRESSURE: 3,
    MG_DEF: 3, VIT_D: 3,
    // Col 4: Autonomic / Reflux Mechanisms
    SYMPATHETIC: 4, ACID: 4, PEPSIN: 4,
    TLESR: 4, GABA_DEF: 4, DOPAMINE: 4,
    // Col 5: Vagal Signaling
    VAGAL: 5,
    // Col 6: Arousal Convergence
    MICRO: 6,
    // Col 7: Central Motor Event
    RMMA: 7,
    // Col 8: Primary Effects & Structural
    GRINDING: 8, TMD: 8, SALIVA: 8, FHP: 8,
    // Col 9: Secondary Consequences
    CERVICAL: 9, HYOID: 9, CS: 9, TOOTH: 9, HEADACHES: 9, EAR: 9,
    // Col 10: Tertiary Consequences
    WINDUP: 10, NECK_TIGHTNESS: 10, GLOBUS: 10,
};

export const TIER_LABELS = {
    1: '1', 2: '2', 3: '3', 4: '4', 5: '5',
    6: '6', 7: '7', 8: '8', 9: '9', 10: '10',
};

export const NUM_TIERS = 10;

// Intervention column assignments (half-column positions between main columns)
export const INTERVENTION_COLUMNS = {
    // Col 0.5 (before root triggers)
    OSA_TX: 0.5, SSRI_TX: 0.5,
    // Col 1.5 (targeting col 2 inputs)
    CBT_TX: 1.5, MINDFULNESS_TX: 1.5, NATURE_TX: 1.5,
    EXERCISE_TX: 1.5, SCREENS_TX: 1.5,
    CIRCADIAN_TX: 1.5, SLEEP_HYG_TX: 1.5, TONGUE_TX: 1.5,
    // Col 2.5 (targeting col 3 disease states & deficiencies)
    MORNING_FAST_TX: 2.5, REFLUX_DIET_TX: 2.5, MEAL_TIMING_TX: 2.5,
    BED_ELEV_TX: 2.5, PPI_TX: 2.5, BREATHING_TX: 2.5, YOGA_TX: 2.5,
    VIT_D_TX: 2.5, MULTI_TX: 2.5,
    // Col 3.5 (targeting col 4 mechanisms)
    WARM_SHOWER_TX: 3.5, HYDRATION: 3.5, NEUROSYM_TX: 3.5,
    MG_SUPP: 3.5, THEANINE_TX: 3.5, GLYCINE_TX: 3.5,
    // Col 6.5 (targeting RMMA)
    BIOFEEDBACK_TX: 6.5, JAW_RELAX_TX: 6.5, BOTOX_TX: 6.5,
    // Col 7.5 (targeting col 8 effects & FHP)
    PHYSIO_TX: 7.5, MASSAGE_TX: 7.5, HEAT_TX: 7.5, POSTURE_TX: 7.5,
    // Col 8.5 (targeting col 9 consequences)
    SPLINT: 8.5,
};

// Intervention categories for the sidebar panel
export const INTERVENTION_CATEGORIES = [
    { name: 'Reflux', items: ['PPI_TX', 'MORNING_FAST_TX', 'REFLUX_DIET_TX', 'MEAL_TIMING_TX', 'BED_ELEV_TX', 'HYDRATION'] },
    { name: 'Sleep', items: ['SCREENS_TX', 'CIRCADIAN_TX', 'SLEEP_HYG_TX', 'WARM_SHOWER_TX'] },
    { name: 'Stress', items: ['CBT_TX', 'MINDFULNESS_TX', 'NATURE_TX', 'EXERCISE_TX', 'BREATHING_TX'] },
    { name: 'Neurochemistry', items: ['MG_SUPP', 'THEANINE_TX', 'GLYCINE_TX', 'YOGA_TX', 'MULTI_TX', 'VIT_D_TX'] },
    { name: 'Neuromodulation', items: ['NEUROSYM_TX', 'BIOFEEDBACK_TX'] },
    { name: 'Motor / Jaw', items: ['JAW_RELAX_TX', 'BOTOX_TX'] },
    { name: 'Physical Therapy', items: ['PHYSIO_TX', 'MASSAGE_TX', 'HEAT_TX', 'POSTURE_TX'] },
    { name: 'Dental / Airway', items: ['SPLINT', 'OSA_TX', 'SSRI_TX', 'TONGUE_TX'] },
];
