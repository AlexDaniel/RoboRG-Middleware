#!/usr/bin/env python3
# Copyright © 2018-2019
#     Aleks-Daniel Jakimenko-Aleksejev <alex.jakimenko@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

import matplotlib.pyplot as plt
import collections
import sys
import select

maxlen = 30


plt.figure()
plt.ion()
plt.show()

data = []
lines = []

while True:
    line = input()
    words = line.split(';')
    if len(words) > len(data):
        for i in range(len(words) - len(data)):
            d = collections.deque(maxlen=maxlen)
            ln, = plt.plot([])
            data.append(d)
            lines.append(ln)

    if select.select([sys.stdin,],[],[],0.0)[0]:
        continue # keep reading for now

    plt.pause(0.05)

    for i in range(len(lines)):
        d  = data[i]
        d.append(float(words[i]))
        ln = lines[i]
        ln.set_xdata(range(len(d)))
        ln.set_ydata(d)

    ax = plt.gca()
    ax.relim()
    bottom, top = ax.get_ylim()
    ax.set_ylim(bottom=min(bottom, -1), top=max(top, 1))
    ax.autoscale_view()
    plt.draw()
