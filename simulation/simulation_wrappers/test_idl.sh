#!/bin/bash

# Run in an interactive session to run interactive tests of FHD simulation

#idl -args 'threeant_mwa_0' '~/data/alanman/FHD_TEST/' 'test'


#idl -args '1066675616' '~/data/alanman/FHD_TEST/' 'sim_mwa_fornax_eor_meta'


#idl -args 'zen.2457458.17389.xx.HH.uvcU' '~/data/alanman/FHD_TEST/' 'sim_heraplat_30min'

#idl -args 'HERA19_0' '~/data/laanman/FHD_TEST'/ 'sim_eor_hera19_mwabeam_test'

idl -args 'hera_platinum_0' '~/data/alanman/FHD_TEST'/ 'sim_hera19_eor' 'kbinsize=0.06'
