Module model_input_ascii

  Contains

    Subroutine read_thermo_file( thermo_file, thermo_desc, ierr, mask_in )
    !-----------------------------------------------------------------------------------------------
    ! Read the thermdynamic trajectory
    !-----------------------------------------------------------------------------------------------
    Use, Intrinsic :: iso_fortran_env, Only: iostat_end
!   Use neutrino_data, Only: fluxcms, tmevnu                                                    !NNU
    Use xnet_controls, Only: idiag, lun_diag, lun_th, nzone, szbatch, nzbatchmx, lzactive
    Use xnet_util, Only: replace_tabs, readnext, xnet_terminate
    Use xnet_conditions, Only: nhmx,nh,tstart,tstop,tdelstart,th,t9h,rhoh,yeh
    Implicit None

    ! Input variables
    Character(*), Intent(in) :: thermo_file(nzone)

    ! Output variables
    Character(80), Intent(out) :: thermo_desc(nzbatchmx)
    Integer, Intent(out) :: ierr

    ! Optional variables
    Logical, Optional, Target, Intent(in) :: mask_in(:)

    ! Local variables
    Integer, Parameter :: max_line_length = 1024
    Integer :: pos, i, n, izb, izone
    Character(max_line_length) :: line
    Logical, Pointer :: mask(:)

    If ( present(mask_in) ) Then
      mask => mask_in
    Else
      mask => lzactive
    EndIf
    If ( .not. any(mask(:)) ) Return

    ! Initialize
    tstart = 0.0
    tstop = 0.0
    tdelstart = 0.0
    th = 0.0
    t9h = 0.0
    rhoh = 0.0
    yeh = 0.0
!   fluxcms = 0.0                                                                               !NNU
!   tmevnu = 0.0                                                                                !NNU
    ierr = 0

    !$omp critical(th_read)
    Do izb = 1, nzbatchmx
      If ( mask(izb) ) Then
        izone = izb + szbatch - 1

        Open(newunit=lun_th, file=trim(thermo_file(izone)), action='read', status='old', iostat=ierr)
        If ( ierr /= 0 ) Then
          Call xnet_terminate('Failed to open input file: '//trim(thermo_file(izone)))
        EndIf

        Read(lun_th,*) thermo_desc(izb)
        Read(lun_th,*) tstart(izb)
        Read(lun_th,*) tstop(izb)
        Read(lun_th,*) tdelstart(izb)
        Do n = 1, nhmx
          line(:) = ' '
          Read(lun_th,"(a)",iostat=ierr) line
          If ( ierr == iostat_end ) Then
            If ( idiag >= 1 ) Write(lun_diag,"(a,i6,a)") 'End of Thermo File Reached after ',n,' records'
            Exit
          ElseIf ( ierr /= 0 ) Then
            Call xnet_terminate('Failed while trying to read input file: '//trim(thermo_file(izone)),ierr)
          Else
            ! Parse the line as space delimited, one value at a time since the format could vary
            Call replace_tabs(line)

            ! Read the required data
            pos = 1
            Call readnext(line,pos,th(n,izb))
            Call readnext(line,pos,t9h(n,izb))
            Call readnext(line,pos,rhoh(n,izb))
            If ( pos == 0 ) Call xnet_terminate('Not enough columns in thermo file: '//trim(thermo_file(izone)))

            ! See if electron fraction is in file, otherwise continue to next line
            Call readnext(line,pos,yeh(n,izb))
            If ( pos == 0 ) Cycle

            ! See if neutrino data is in file, otherwise continue to next line
!           Do i = 1, 4                                                                         !NNU
!             Call readnext(line,pos,fluxcms(n,i,izb))                                          !NNU
!           EndDo                                                                               !NNU
!           If ( pos == 0 ) Cycle                                                               !NNU
!           Do i = 1, 4                                                                         !NNU
!             Call readnext(line,pos,tmevnu(n,i,izb))                                           !NNU
!           EndDo                                                                               !NNU
          EndIf
        EndDo
        nh(izb) = n - 1
        Close(lun_th)

        ! Do not use tdelstart from thermo files
        tdelstart(izb) = min(0.0,tdelstart(izb))

        ! Log thermo description
        If ( idiag >= 0 ) Write(lun_diag,"(a)") thermo_desc(izb)
      EndIf
    EndDo
    !$omp end critical(th_read)

    ! Convert to appropriate units (CGS, except temperature (GK) and neutrino flux)
!   t9h = t9h * 1.0e-9
!   fluxcms = 1.0e-42 * fluxcms                                                                 !NNU

    Return
  End Subroutine read_thermo_file

  Subroutine load_initial_abundances( inab_file, abund_desc, ierr, mask_in )
    !-----------------------------------------------------------------------------------------------
    ! This routine loads the initial abundances at the start time by reading the initial abundance
    ! file or by generating an NSE composition.
    !-----------------------------------------------------------------------------------------------
    Use nuclear_data, Only: ny, nname
    Use xnet_conditions, Only: nstart, tstart, t9start, rhostart, yestart, nh, th, yeh
    USe xnet_abundances, Only: y_moment, ystart
    Use xnet_controls, Only: lun_diag, idiag, t9nse, nzone, szbatch, nzbatchmx, lzactive
    Use xnet_nse, Only: nse_solve, ynse
    Use xnet_types, Only: dp
    Implicit None

    ! Input variables
    Character(*), Intent(in) :: inab_file(nzone)

    ! Output variables
    Character(80), Intent(out) :: abund_desc(nzbatchmx)
    Integer, Intent(out) :: ierr

    ! Optional variables
    Logical, Optional, Target, Intent(in) :: mask_in(:)

    ! Local variables
    Real(dp) :: yein, yin(ny)
    Real(dp) :: rdt, dt, dye
    Real(dp) :: ytot, abar, zbar, z2bar, zibar
    Integer :: i, izb, izone
    Logical, Pointer :: mask(:)

    If ( present(mask_in) ) Then
      mask => mask_in(:)
    Else
      mask => lzactive(:)
    EndIf
    If ( .not. any(mask(:)) ) Return

    ! Initialize
    yestart = 0.0
    ystart(:,:) = 0.0
    ierr = 0

    Do izb = 1, nzbatchmx
      If ( mask(izb) ) Then
        izone = izb + szbatch - 1

        ! Interpolate electron fraction from thermo file
        If ( nstart(izb) > 1 .and. nstart(izb) <= nh(izb) ) Then
          rdt = 1.0 / ( th(nstart(izb),izb) - th(nstart(izb)-1,izb) )
          dt = tstart(izb) - th(nstart(izb)-1,izb)
          dye = yeh(nstart(izb),izb) - yeh(nstart(izb)-1,izb)
          yestart(izb) = dt*rdt*dye + yeh(nstart(izb)-1,izb)
        ElseIf ( nstart(izb) == 1 ) Then
          yestart(izb) = yeh(1,izb)
        Else
          yestart(izb) = yeh(nh(izb),izb)
        EndIf

        ! Read the initial abundance file if not in NSE or if invalid Ye from thermo file
        If ( t9start(izb) <= t9nse .or. yestart(izb) <= 0.0 .or. yestart(izb) >= 1.0 ) Then
          Call read_inab_file(inab_file(izone),abund_desc(izb),yein,yin,ierr)

          ! If Ye is not provided in the initial abundance file explicitly, calculate it here
          If ( yein <= 0.0 .or. yein >= 1.0 ) Call y_moment(yin,yein,ytot,abar,zbar,z2bar,zibar)
          yestart(izb) = yein

          ! Log abundance file and description
          If ( idiag >= 0 ) Then
            Write(lun_diag,"(a)") inab_file(izone)
            Write(lun_diag,"(a)") abund_desc(izb)
          EndIf
        EndIf

        If ( idiag >= 0 ) Write(lun_diag,"(a,i6,a,f6.3,a,es10.3,a,f5.4)") &
          & 'Start',nstart(izb),' T9=',t9start(izb),' Rho=',rhostart(izb),' Ye=',yestart(izb)

        ! For high temperatures, use NSE to get initial abundance
        If ( t9start(izb) > t9nse ) Then
          If ( idiag >= 0 ) Write(lun_diag,"(a)") 'Initial abundances from NSE'
          Call nse_solve(rhostart(izb),t9start(izb),yestart(izb))
          ystart(:,izb) = ynse(:)
        Else
          ystart(:,izb) = yin(:)
        EndIf

        ! Log initial abundance
        If ( idiag >= 0 ) Write(lun_diag,"(5(a6,1es10.3))") (nname(i), ystart(i,izb), i=1,ny)
      EndIf
    EndDo

    Return
  End Subroutine load_initial_abundances

  Subroutine read_inab_file( inab_file, abund_desc, yein, yin, ierr )
    !-----------------------------------------------------------------------------------------------
    ! This routine reads initial abundances from a supplied input file.
    !-----------------------------------------------------------------------------------------------
    Use, Intrinsic :: iso_fortran_env, Only: iostat_end
    Use nuclear_data, Only: ny, aa, zz, index_from_name
    Use xnet_controls, Only: lun_stderr, lun_ab, lun_diag, idiag
    Use xnet_types, Only: dp
    Use xnet_util, Only: string_lc, xnet_terminate
    Implicit None

    ! Input variables
    Character (*), Intent(in) :: inab_file

    ! Output variables
    Character(80), Intent(out) :: abund_desc
    Real(dp), Intent(out) :: yein
    Real(dp), Intent(out) :: yin(ny)
    Integer, Intent(out) :: ierr

    ! Local variables
    Integer, Parameter :: nread_max = 4 ! Maximum number of abundance entries to read at once
    Character(5) :: char_tmp(nread_max), namein
    Real(dp) :: real_tmp(nread_max), xnet, znet, yext, xext, aext, zext
    Integer :: i, inuc

    ! Initialize
    yein = 0.0
    yin(:) = 0.0
    yext = 0.0

    !$omp critical(ab_read)
    Open(newunit=lun_ab, file=trim(inab_file), action='read', status='old', iostat=ierr)
    If ( ierr /= 0 ) Then
      Write(lun_stderr,"(2a)") 'Failed to open input file: ',trim(inab_file)
    Else

      Read(lun_ab,*) abund_desc
      Do
        char_tmp(:) = '     '
        real_tmp(:) = 0.0

        ! Read nread_max entries at once, for backwards compatability with multiple entries per line
        Read(lun_ab,*,iostat=ierr) (char_tmp(i), real_tmp(i), i=1,nread_max)
        If ( ierr == iostat_end ) Then
          Exit
        ElseIf ( ierr /= 0 ) Then
          Write(lun_stderr,"(3a,i4,a)") 'Failed while trying to read input file: ',trim(inab_file),' (',ierr,')'
          Call xnet_terminate('Failed while trying to read input file: '//trim(inab_file),ierr)
        EndIf

        ! Process each entry, chceking for special cases and converting names to lower-case
        Do i = 1, nread_max
          namein = adjustl(char_tmp(i))
          If ( len_trim(namein) > 0 .and. real_tmp(i) > 0.0 ) Then
            Call string_lc(namein)

            If ( trim(namein) == 'ye' ) Then
              yein = real_tmp(i)
            Else
              Call index_from_name(namein,inuc)
              If ( inuc < 1 .or. inuc > ny ) Then
                If ( idiag >= 0 ) Write(lun_diag,"(3a)") 'Input Nuc: ',namein,' not found'
                yext = yext + real_tmp(i)
              Else
                yin(inuc) = real_tmp(i)
              EndIf
            EndIf
          EndIf
        EndDo
      EndDo

      ! If the number of species isn't divisible by 4, we need to parse the last few entries here
      Do i = 1, nread_max
        namein = adjustl(char_tmp(i))
        If ( len_trim(namein) > 0 .and. real_tmp(i) > 0.0 ) Then
          Call string_lc(namein)

          If ( trim(namein) == 'ye' ) Then
            yein = real_tmp(i)
          Else
            Call index_from_name(namein,inuc)
            If ( inuc < 1 .or. inuc > ny ) Then
              If ( idiag >= 0 ) Write(lun_diag,"(3a)") 'Input Nuc: ',namein,' not found'
              yext = yext + real_tmp(i)
            Else
              yin(inuc) = real_tmp(i)
            EndIf
          EndIf
        EndIf
      EndDo
      Close(lun_ab)

      ! Total mass fraction inside network
      xnet = sum(yin(:)*aa(:))
      znet = sum(yin(:)*zz(:))
      If ( idiag >= 1 ) Write(lun_diag,"(a,4es15.7)") 'ynet, xnet, anet, znet: ',sum(yin(:)),xnet,xnet,znet

      ! Normalize so total mass fraction is one
      yin(:) = yin(:) / xnet

      ! Calculate properties of matter not in network
      If ( yext > 0.0 ) Then
        xext = 1.0 - xnet
        aext = xext / yext
        zext = ( yein - znet ) * aext / xext
        If ( idiag >= 1 ) Write(lun_diag,"(a,4es15.7)") 'yext, xext, aext, zext: ',yext,xext,aext,zext
      EndIf
    EndIf
    !$omp end critical(ab_read)

    Return
  End Subroutine read_inab_file

End Module model_input_ascii
