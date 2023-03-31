#!/usr/bin/python3

import json
import os
import sys

from gi.repository import GLib
from pydbus import SystemBus

bat_levels = {
        9: 'critical',
        12: 'warning'
        }

bat_states = {
        0: 'unknown',
        1: 'charging',
        2: 'discharging',
        3: 'empty',
        4: 'full',
        5: 'charge_pending',
        6: 'discharge_pending'
        }

CSS_CLASS_DISCONNECTED = 'disconnected'

class BatteryWatcher:
    loop = None
    dbus = None
    upower = None
    bat_name = None
    bat_obj_path = None
    bat = None
    bat_design_capacity = None
    bat_percentage_of_design = None
    bat_percentage_of_current = None
    bat_state = None

    def __init__(self, battery_name="BAT0"):
        self.loop = GLib.MainLoop()
        self.bat_name = battery_name
        self.dbus = SystemBus()
        self.upower = self.dbus.get('org.freedesktop.UPower',
                '/org/freedesktop/UPower')
        self.bat_obj_path = '/org/freedesktop/UPower/devices/battery_{}'\
                .format(self.bat_name)

    def run(self):
        if self.bat_obj_path in self.upower.EnumerateDevices():
            self.upower.onDeviceRemoved = self.onDeviceRemoved
            self.add_battery()
        else:
            self.upower.onDeviceAdded = self.onDeviceAdded

        self.export_state()
        self.loop.run()

    def add_battery(self):
        self.bat = self.dbus.get(
           'org.freedesktop.UPower', self.bat_obj_path)

        self.bat.onPropertiesChanged = self.onPropertiesChanged

        self.bat_design_capacity = self.bat.EnergyFullDesign
        self.bat_percentage_of_design = \
           (self.bat.Energy / self.bat_design_capacity) * 100
        self.bat_percentage_of_current = self.bat.Percentage
        self.bat_state = self.bat.State

    def remove_battery(self):
        self.bat.onPropertiesChanged = None
        self.bat = None

    def export_state(self):
        if self.bat:
            percentage = int(round(self.bat_percentage_of_current))
            text = str(int(round(self.bat_percentage_of_design))) + "%"
            css_classes = [ bat_states[self.bat.State] ]

            for level in bat_levels.keys():
                if self.bat_percentage_of_design <= level:
                    css_classes.append(bat_levels[level])
                    break
        else:
            percentage = 0
            text = "N/A"
            css_classes = [ CSS_CLASS_DISCONNECTED ]

        output = { 'text': text,
                   'percentage': percentage,
                   'class' : css_classes }

        try:
            print(json.dumps(output), flush=True)
        except BrokenPipeError:
            self.loop.quit()

    def onPropertiesChanged(self, interface_name, changed_properties,
                            invalidated_properties):
        update = False

        if 'Energy' in changed_properties:
            self.bat_percentage_of_design = \
                    (changed_properties['Energy'] / self.bat_design_capacity) \
                    * 100
            update = True
        if 'Percentage' in changed_properties:
            self.bat_percentage_of_current = changed_properties['Percentage']
        if 'State' in changed_properties:
            self.bat_state = changed_properties['State']
            update = True

        if update:
            self.export_state()

    def onDeviceAdded(self, object_path):
        if object_path == self.bat_obj_path:
            self.upower.onDeviceAdded = None
            self.upower.onDeviceRemoved = self.onDeviceRemoved
            self.add_battery()
            self.export_state()

    def onDeviceRemoved(self, object_path):
        if object_path == self.bat_obj_path:
            self.upower.onDeviceAdded = self.onDeviceAdded
            self.upower.onDeviceRemoved = None
            self.remove_battery()
            self.export_state()

def main(argv=None):
    battery_name = "BAT0"

    if len(argv) == 2:
        battery_name = argv[1]
    elif len(argv) > 2:
        print("Error: Too many arguments!", file=sys.stderr)
        return os.EX_USAGE

    try:
        BatteryWatcher(battery_name).run()
    except KeyboardInterrupt:
        return 0
    except BrokenPipeError:
        return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv))
