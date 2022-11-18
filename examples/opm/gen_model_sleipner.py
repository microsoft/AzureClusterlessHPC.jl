#  ------------------------------------------------------------------------------------------
#  Copyright (c) Microsoft Corporation. All rights reserved.
#  Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
#  ------------------------------------------------------------------------------------------

import numpy as np
import matplotlib.pyplot as plt
import h5py

def gen_permeability(nx, ny, nz, feeders=True, constant=None):

    # Permeability in x/y and z
    if constant is None:
        permxy = np.zeros((nx, ny, nz)) # same in x and y
        permz = np.zeros((nx, ny, nz))

        # Create CO2 reservoir
        reservoir_size = int(np.round(nz / 100 * np.random.uniform(low=15, high=25)))
        c = reservoir_size
        pcurr = np.random.uniform(low=3000, high=3500)
        permxy[:,:,0:c] = pcurr
        permz[:,:,0:c] = pcurr

        # Stack additional layers on top
        nz_ = int(np.round(np.random.uniform(low=0.70, high=0.85)*nz))
        while c < nz_:
            
            # Seal
            if nz <= 64:
                seal_width = 1
            else:
                seal_width = int(np.round(np.random.uniform(low=2, high=3)))

            if seal_width + c > nz_:
                seal_width = nz_ - c

            pcurr = np.random.uniform(low=0.001, high=0.003)
            permxy[:,:,c:c+seal_width] = pcurr
            permz[:,:,c:c+seal_width] = pcurr
            if feeders:
                xfeed = nx // 2 #np.random.randint(int(nx/4), int(3*nx/4))
                yfeed = ny // 2 #np.random.randint(int(ny/4), int(3*ny/4))
                permz[xfeed-1:xfeed+1, yfeed-1:yfeed+1, c:c+seal_width] = np.random.uniform(low=1e-1, high=100)
            c += seal_width

            if c >= nz_:
                break

            # Porous layer
            poro_width = int(np.round(nz / 100 * np.random.normal(loc=7.5, scale=2.4)))
            if poro_width + c > nz_:
                poro_width = nz_ - c
            pcurr = np.random.uniform(low=1200, high=3400)
            permxy[:,:,c:c+poro_width] = pcurr
            permz[:,:,c:c+poro_width] = pcurr
            c += poro_width

        while c < nz:
            
            # Seal
            seal_width = int(np.round(nz / 100 * np.random.uniform(low=3, high=6)))
            if seal_width + c > nz:
                seal_width = nz - c
            pcurr = np.random.uniform(low=0.001, high=0.003)
            permxy[:,:,c:c+seal_width] = pcurr
            permz[:,:,c:c+seal_width] = pcurr
            if feeders:
                xfeed = nx // 2 #np.random.randint(int(nx/4), int(3*nx/4))
                yfeed = ny // 2 #np.random.randint(int(ny/4), int(3*ny/4))
                permz[xfeed-1:xfeed+1, yfeed-1:yfeed+1, c:c+seal_width] = np.random.uniform(low=0.01, high=0.3)
            c += seal_width

            if c >= nz:
                break

            # Porous layer
            poro_width = int(np.round(nz / 100 * np.random.normal(loc=7.5, scale=2.4)))
            if poro_width + c > nz:
                poro_width = nz - c
            pcurr = np.random.uniform(low=1000, high=2000)
            permxy[:,:,c:c+poro_width] = pcurr
            permz[:,:,c:c+poro_width] = pcurr
            c += poro_width
    else:
        permxy = constant*np.ones((nx, ny, nz)) # same in x and y
        permz = constant*np.ones((nx, ny, nz)) / 100

    return np.flip(permxy, axis=2), np.flip(permz, axis=2)



def gen_tops(nx, ny, filename='sleipner_tops_orig.h5', constant=None):

    if constant is None:
        fid = h5py.File(filename, 'r')
        tops_orig = np.array(fid['tops'])

        # Transpose?
        transpose = np.random.randint(0,2)
        if transpose:
            tops_orig = np.transpose(tops_orig)

        # Vertical flip?
        flip_vert = np.random.randint(0,2)
        if flip_vert:
            tops_orig = np.flip(tops_orig, axis=0)

        # Horizontal flip?
        flip_hor = np.random.randint(0,2)
        if flip_hor:
            tops_orig = np.flip(tops_orig, axis=1)

        # Flip elevation?
        flip_elev = np.random.randint(0,2)
        if flip_hor:
            tops_orig = np.abs(tops_orig - 1)

        # Extract random section
        nx_, ny_ = tops_orig.shape
        xmax = nx_ - nx
        if xmax > 0:
            xmin = np.random.randint(0, xmax)
        else:
            xmin = 0

        ymax = ny_ - ny
        if ymax > 0:
            ymin = np.random.randint(0, ymax)
        else:
            ymin = 0
            
        tops = tops_orig[xmin:xmin+nx, ymin:ymin+ny]

        tmin = np.min(tops)
        tmax = np.max(tops)
        tops = tops - tmin
        tops = tops / np.max(tops)
        tops = tops * 100
        tops += 700
    else:
        tops = np.ones((nx, ny)) * constant

    return tops


def gen_spacing(nx, ny, nz, nb=4):

    if nb > 1:
        dx = np.ones((nx, ny, nz)) * 50
        dy = np.ones((nx, ny, nz)) * 50
        dz = np.ones((nx, ny, nz)) * 5

        dxy_dec = np.linspace(500, 50, nb+1)
        #dz_dec = np.linspace(50, 5, nb+1)

        for i in range(1,nb+1):
            dx[i:-i, i:-i, i:-i] = dxy_dec[i]
            dy[i:-i, i:-i, i:-i] = dxy_dec[i]
            #dz[i:-i, i:-i, i:-i] = dz_dec[i]
    else:
        dx = np.ones((nx, ny, nz)) * 30
        dy = np.ones((nx, ny, nz)) * 30
        dz = np.ones((nx, ny, nz)) * 5

    return dx, dy, dz


def gen_sleipner(nx, ny, nz, nbpml, sx, sy, sz1, sz2, filename='sleipner_tops_orig.h5', permval=None, topsval=None, poroval=0.3):

    # Gen model and topography
    permxy, permz = gen_permeability(nx + 2*nbpml, ny + 2*nbpml, nz + 2*nbpml, constant=permval)
    tops = gen_tops(nx + 2*nbpml, ny + 2*nbpml, filename=filename, constant=topsval)
    dx, dy, dz = gen_spacing(nx + 2*nbpml, ny + 2*nbpml, nz + 2*nbpml, nb=nbpml)
    poro = np.ones((nx + 2*nbpml, ny + 2*nbpml, nz + 2*nbpml))*poroval

    # From {x,y,z} to {z,y,x} for OPM Flow
    permxy  = permxy.transpose(2, 1, 0)
    permz  = permz.transpose(2, 1, 0)
    poro = poro.transpose(2, 1, 0)
    dx = dx.transpose(2, 1, 0)
    dy = dy.transpose(2, 1, 0)
    dz = dz.transpose(2, 1, 0)
    tops = tops.transpose(1, 0)

    # Write dimensions
    dimtxt = open('DIMENS.txt', 'w')
    dimtxt.write('DIMENS\n{} {} {}/'.format(nx + 2*nbpml, ny + 2*nbpml, nz + 2*nbpml))
    dimtxt.close()

    # Create grid and perm files
    np.savetxt('PERMX.txt', permxy.flatten().reshape((-1, 8)), delimiter='\t', header='PERMX', comments='', fmt='%.6f', footer='/')
    np.savetxt('PERMY.txt', permxy.flatten().reshape((-1, 8)), delimiter='\t', header='PERMY', comments='', fmt='%.6f', footer='/')
    np.savetxt('PERMZ.txt', permz.flatten().reshape((-1, 8)), delimiter='\t', header='PERMZ', comments='', fmt='%.6f', footer='/')
    np.savetxt('PORO.txt', poro.flatten().reshape((-1, 8)), delimiter='\t', header='PORO', comments='', fmt='%.6f', footer='/')
    np.savetxt('DX.txt', dx.flatten().reshape((-1, 8)), delimiter='\t', header='DX', comments='', fmt='%.6f', footer='/')
    np.savetxt('DY.txt', dy.flatten().reshape((-1, 8)), delimiter='\t', header='DY', comments='', fmt='%.6f', footer='/')
    np.savetxt('DZ.txt', dz.flatten().reshape((-1, 8)), delimiter='\t', header='DZ', comments='', fmt='%.6f', footer='/')
    np.savetxt('TOPS.txt', tops.flatten().reshape( (-1, 8)), delimiter='\t', header='TOPS', comments='', fmt='%.6f', footer='/')

    # Write well specs
    welltxt = open('WELSPECS.txt', 'w')
    welltxt.write('WELSPECS\nInjector I {} {} 0.0e+00 WATER 0 STD SHUT NO 0 SEG 0/'.format(sx + nbpml, sy + nbpml))
    welltxt.close()

    # Write comp dat
    comptxt = open('COMPDAT.txt', 'w')
    comptxt.write('COMPDAT\n')
    comptxt.write('Injector {} {} {} {} OPEN -1 8.5107288246779274e+02 2.0e-01 -1.0 0 1* Y -1.0/\n'.format(\
        sx + nbpml, sy + nbpml, sz1 + nbpml, sz2 + nbpml))
    comptxt.write('Injector {} {} {} {} OPEN -1 4.0622380088359796e+02 2.0e-01 -1.0 0 1* Y -1.0/'.format(\
        sx + nbpml, sy + nbpml, sz1 + nbpml, sz2 + nbpml))
    comptxt.close()

    # Transpose to original order
    permxy  = permxy.transpose(2, 1, 0)
    permz  = permz.transpose(2, 1, 0)
    poro = poro.transpose(2, 1, 0)
    dx = dx.transpose(2, 1, 0)
    dy = dy.transpose(2, 1, 0)
    dz = dz.transpose(2, 1, 0)
    tops = tops.transpose(1, 0)

    return permxy, permz, poro, tops, dx, dy, dz