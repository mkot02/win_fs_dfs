__metaclass__ = type


def unc_path(*args, **kwargs):
    path = '\\\\' + '\\'.join(args)
    return path


class FilterModule(object):
    """ Common infrastructure modules """

    def filters(self):
        return {
            "unc_path": unc_path,
        }
