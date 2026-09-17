"""Detect host-clock discontinuities instead of calling them execution savings."""
import time

CLOCK_TOLERANCE_SECONDS=2.0


def observe(start_wall,start_monotonic,ceiling=float('inf')):
    wall=time.time()-start_wall
    monotonic=time.monotonic()-start_monotonic
    difference=wall-monotonic
    return {'wall_seconds':round(wall,3),'monotonic_seconds':round(monotonic,3),
            'clock_difference_seconds':round(difference,3),
            'timing_valid':wall>=0 and monotonic>=0 and abs(difference)<=CLOCK_TOLERANCE_SECONDS,
            'within_ceiling':max(wall,monotonic)<=ceiling}
