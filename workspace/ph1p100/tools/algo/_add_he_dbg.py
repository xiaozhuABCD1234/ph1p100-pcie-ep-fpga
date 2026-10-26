# -*- coding: utf-8 -*-
"""Historical helper (round1 debugging): it inserted/removed a temporary HE debug
block in tools/algo/tb/tb_img_algo_core.sv.  The debug block has been removed
from the testbench and the candidate is frozen; this file is intentionally a
no-op so it cannot mutate the frozen testbench if executed by mistake.

Not part of candidate-manifest.json.
"""
print("no-op: the TB debug block was removed before the round1 freeze")
