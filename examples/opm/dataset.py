#  ------------------------------------------------------------------------------------------
#  Copyright (c) Microsoft Corporation. All rights reserved.
#  Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
#  ------------------------------------------------------------------------------------------

import h5py, zarr, os
import numpy as np 
import torch
from torch.utils.data import Dataset 

class SleipnerDataset4D(Dataset):
    ''' Dataset class for flow data generated with OPM 
    This dataset class repeats 3D models in the temporal dimension
    '''

    def __init__(self, index=None, client=None, container=None, path=None, shape=None, nt=None, normalize=True, padding=None, savepath=None, filename=None, keep_data=False):
        """ Pytorch dataset class for Sleipner data set.
        """

        self.samples = index
        self.client = client
        self.container = container
        self.prefix = path
        self.nt = nt
        self.normalize = normalize
        self.padding = padding
        self.shape = shape
        self.savepath = savepath
        self.keep_data = keep_data
        self.filename = filename
        if savepath is not None:
            self.cache = list()
            # Check if files were already downloaded
            files = os.listdir(savepath)
            for i in samples:
                if filename + '_' + str(int(i.item())) + '.h5' in files:
                    self.cache.append(self.filename + '_' + str(i.item()) + '.h5')
        else:
            self.cache = None

        # Open the data file
        self.store = zarr.ABSStore(container=self.container, prefix=self.prefix, client=self.client)       

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, index):
        
        # Read 
        i = int(self.samples[index])

        # If caching is used, check if data sample exists locally
        if self.cache is not None and self.filename + '_' + str(i) + '.h5' in self.cache:
            fid = h5py.File(os.path.join(self.savepath, self.filename + '_' + str(i) + '.h5'), 'r')
            x = torch.tensor(np.array(fid['x']))
            sat = torch.tensor(np.array(fid['y']))
            fid.close()

        else:
            nx, ny, nz = self.shape
            
            permxy = torch.tensor(np.array(zarr.core.Array(self.store, path='permxy_' + str(i))), dtype=torch.float32)      # XYZ
            permz = torch.tensor(np.array(zarr.core.Array(self.store, path='permz_' + str(i))), dtype=torch.float32)        # XYZ
            tops = torch.tensor(np.array(zarr.core.Array(self.store, path='tops_' + str(i))), dtype=torch.float32)          # YZ
            sat = torch.tensor(np.array(zarr.core.Array(self.store, path='saturation_' + str(i))), dtype=torch.float32)     # XYZT
            pressure = torch.tensor(np.array(zarr.core.Array(self.store, path='pressure_' + str(i))), dtype=torch.float32)  # XYZT
            well = torch.zeros(nx, ny, nz, 1)
            well[30, 30, :, 0] = 1.0

            # Copy tops
            tops = tops.view(1, ny, nz).repeat(nx, 1, 1)

            # Normalize
            if self.normalize:
                permxy -= permxy.min(); permxy /= permxy.max()
                permz -= permz.min(); permz /= permz.max()
                tops -= tops.min(); tops /= tops.max()
                well -= well.min(); well /= well.max()
                sat -= sat.min(); sat /= sat.max()
                sat[sat < 0] = 0; sat /= sat.max()
                pressure -= pressure.min(); pressure /= pressure.max()         

            # Padding
            if self.padding is not None:
                xpad, ypad, zpad = self.padding
                permxy = torch.nn.functional.pad(permxy, (zpad,zpad,ypad,ypad,xpad,xpad))
                permz = torch.nn.functional.pad(permz, (zpad,zpad,ypad,ypad,xpad,xpad))
                tops = torch.nn.functional.pad(tops, (zpad,zpad,ypad,ypad,xpad,xpad))
                well = torch.nn.functional.pad(well, (zpad,zpad,ypad,ypad,xpad,xpad))
                sat = torch.nn.functional.pad(sat, (0,0,zpad,zpad,ypad,ypad,xpad,xpad))
                pressure = torch.nn.functional.pad(pressure, (0,0,zpad,zpad,ypad,ypad,xpad,xpad))
                nx, ny, nz, nt = pressure.shape
                self.shape = nx, ny, nz

            # Repeat along time
            permxy = permxy.view(nx, ny, nz, 1, 1).repeat(1, 1, 1, self.nt, 1)  # X Y Z T C=1
            permz = permz.view(nx, ny, nz, 1, 1).repeat(1, 1, 1, self.nt, 1)    # X Y Z T C=1
            tops = tops.view(nx, ny, nz, 1, 1).repeat(1, 1, 1, self.nt, 1)      # X Y Z T C=1
            well = well.view(nx, ny, nz, 1, 1).repeat(1, 1, 1, self.nt, 1)      # X Y Z T C=1
            sat = sat.view(nx, ny, nz, self.nt, 1)                              # X Y Z T C=1
            pressure = pressure.view(nx, ny, nz, self.nt, 1)                    # X Y Z T C=1

            x = torch.cat((
                permz,
                tops
                ),
                axis=-1
            )

            if self.cache is not None:
                fid = h5py.File(os.path.join(self.savepath, self.filename + '_' + str(i) + '.h5'), 'w')
                fid.create_dataset('x', data=x)
                fid.create_dataset('y', data=sat)
                fid.close()
                self.cache.append(self.filename + '_' + str(i) + '.h5')

        return x, sat
        
    def close(self):
        if self.keep_data is False and self.cache is not None:
            print('Delete temp files.')
            for file in self.cache:
                os.system('rm ' + self.savepath + '/' + file)
