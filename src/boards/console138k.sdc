# The controller USB engines and the video/control logic use independent PLLs.
# Constrain only the asynchronous inputs to the explicit first synchronizer
# stage; all paths after this stage remain normally timed.
set_false_path -to [get_regs {joy_usb1_meta* joy_usb2_meta* controller_status_meta*}]
