#!/usr/bin/env python3
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
