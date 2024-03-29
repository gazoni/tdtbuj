!> \brief self consistent field method
!> \author Alin M Elena
!> \date 05/11/07, 10:30:06
module m_SCF
  use m_Constants
  use m_Types
  use m_Useful
  use m_Gutenberg
  use m_Hamiltonian
  use m_LinearAlgebra, only: MatrixTrace, CopyMatrix, SpmPut, MatrixCeaApbB
  use m_Electrostatics
  use m_TightBinding
  use m_DensityMatrix
  use m_Mixing
  implicit none
  private
!
  public :: FullScf
  public :: ScfEnergy
  public :: ScfForces
  public :: AddH2
!
  interface SCFChargeNumbers
    module procedure SCFChargeNumbersSpin, SCFChargeNumbersSpinLess, SCFChargeNumbersLSpinLess, SCFChargeNumbersLSpin
  end interface
!
contains
!
!> \brief controls the scf calculation.
!> \details practically computes a single point calculation (energy and forces)
!> if you asked for a SCF calculation the scf path is followed
!> \author Alin M Elena
!> \date 05/11/07, 10:33:06
!> \param ioLoc type(ioType) contains all the info about I/O files
!> \param genLoc type(generalType) contains the info needed by the program to run
!> \param atomic type(atomicxType) contains all info about the atoms and basis set and some parameters
!> \param tbMod type(modelType) contains information about the tight binding model parameters
!> \param sol type(solutionType) contains information about the solution space
  subroutine FullScf (ioLoc, genLoc, atomic, tbMod, sol)
    character (len=*), parameter :: sMyName = "FullScf"
    type (ioType), intent (inout) :: ioLoc
    type (generalType), intent (inout) :: genLoc
    type (atomicxType), intent (inout) :: atomic
    type (modelType), intent (inout) :: tbMod
    type (solutionType), intent (inout) :: sol
    integer :: nit, m, n
    real (k_pr) :: residual, dmax
    real (k_pr) :: ee, re, scfe, te
    logical :: exists, first
    integer :: ierr
    integer :: l, ml, i, j, nmix
    complex (k_pr) :: trace
    character (len=k_ml) :: saux
    character (len=k_mw) :: labels (1:4), labelsH2 (1:4)
    dmax = 0.0_k_pr
    genLoc%lIsSCFConverged = .true.
    n = atomic%basis%norbitals
    m = (n-1) * n / 2
    ee = 0.0_k_pr
    re = 0.0_k_pr
    scfe = 0.0_k_pr
    te = 0.0_k_pr
    if (genLoc%scf) then
! delta density matrix is stored in an array as upper triangular part followed by the diagonal
      select case (genLoc%scfType)
      case (k_scfTbuj, k_scfTBu, k_scfTBUO, k_scfTBujo)
!
        sol%buff%dins = 0.0_k_pr
        sol%buff%douts = 0.0_k_pr
        sol%buff%res = 0.0_k_pr
!
        sol%buff%densityin = 0.0_k_pr
        sol%buff%densityout = 0.0_k_pr
        sol%buff%densitynext = 0.0_k_pr
!
        call BuildHamiltonian (ioLoc, genLoc, atomic, tbMod, sol)
        call AddBias (1.0_k_pr, atomic, sol)
        call CopyMatrix (sol%hin, sol%h, ioLoc)
        call DiagHamiltonian (ioLoc, genLoc, atomic, sol)
        if (ioLoc%Verbosity >= k_highVerbos) then
          write (ioLoc%uout, '(a)') "Before entering the SCF LOOP"
          if (genLoc%spin) then
            labels (1) = "Hin: Spin DD"
            labels (2) = "Hin: Spin UU"
            labels (3) = "Hin: Spin DU"
            labels (4) = "Hin: Spin UD"
            call PrintMatrixBlocks (sol%h, labels, ioLoc, .false., .not. genLoc%collinear)
            labels (1) = "Eigenvectors: Spin DD"
            labels (2) = "Eigenvectors: Spin UU"
            labels (3) = "Eigenvectors: Spin DU"
            labels (4) = "Eigenvectors: Spin UD"
            call PrintMatrixBlocks (sol%eigenvecs, labels, ioLoc, .false., .not. genLoc%collinear)
            labels (1) = "H: Spin DD"
            labels (2) = "H: Spin UU"
            labels (3) = "H: Spin DU"
            labels (4) = "H: Spin UD"
            labelsH2 (1) = "H2: Spin DD"
            labelsH2 (2) = "H2: Spin UU"
            labelsH2 (3) = "H2: Spin DU"
            labelsH2 (4) = "H2: Spin UD"
          else
            call PrintMatrix (sol%h, "Hin: ", ioLoc)
            call PrintMatrix (sol%eigenvecs, "Eigenvectors: ", ioLoc)
          end if
          call PrintOccupationNumbers (genLoc, sol, ioLoc)
          write (ioLoc%uout, "(a,f16.8)") "chemical potential: ", genLoc%electronicMu
          write (ioLoc%uout, '(a,f16.8)') "Entropy term: ", sol%electronicEntropy
          trace = MatrixTrace (sol%rho, ioLoc)
          write (saux, '(a,"(",f0.4,1x,f0.4,"i)")') "Density matrix, Trace= ", trace
          call PrintMatrix (sol%rho, trim(saux), ioLoc)
        end if
!
        call BuildDensity (atomic, sol)
        sol%buff%densityin = sol%density
        if (( .not. genLoc%compElec) .and. (genLoc%electrostatics == k_electrostaticsMultipoles)) then
          call initQvs (atomic, genLoc, sol, tbMod, sol%buff%densityin)
        end if
!
!           scfe=ScfEnergy(genLoc,atomic,sol,ioLoc)
        call CalcExcessCharges (genLoc, atomic, sol)
        call CalcDipoles (genLoc, atomic, sol, tbMod)
        call ComputeMagneticMoment (genLoc, atomic, sol, ioLoc)
        if (ioLoc%Verbosity >= k_highVerbos) then
          do i = 1, atomic%atoms%natoms
            if (genLoc%electrostatics == k_electrostaticsMultipoles) then
              call PrintQlmR (i, genLoc, atomic, sol, tbMod, ioLoc, sol%buff%densityin)
              call PrintVlmR (i, genLoc, atomic, sol, tbMod, ioLoc, sol%buff%densityin)
              do j = 1, atomic%atoms%natoms
                if (i /= j) then
                  call PrintIrregularRealSolidH (i, j, atomic, sol, ioLoc)
                  call PrintBllpR (i, j, atomic, sol, ioLoc)
                end if
              end do
            end if
            call PrintAtomChargeAnalysis (i, atomic, sol, genLoc, ioLoc)
            call PrintAtomMatrix (i, atomic, sol%hin, "Hin", ioLoc, .false.)
            call PrintAtomMatrix (i, atomic, sol%rho, "Density", ioLoc, .false.)
          end do
          call PrintCharges (genLoc, atomic, ioLoc)
          call PrintDipoles (atomic, ioLoc)
          if (genLoc%spin) call PrintMagneticMoment (atomic, sol, .false., ioLoc)
        end if
!
!
        write (ioLoc%uout, '(a)') "SCF"
        write (ioLoc%uout, '(a)') "SCFReport   nit          energy             res           drmax         Tr[rho]             mu"
!
        do nit = 1, genLoc%maxscf
          if (ioLoc%Verbosity >= k_highVerbos) then
            write (ioLoc%uout, '(a,i0)') "SCF LOOP iteration: ", nit
          end if
          if (( .not. genLoc%compElec) .and. (genLoc%electrostatics == k_electrostaticsMultipoles)) then
            call initQvs (atomic, genLoc, sol, tbMod, sol%buff%densityin)
          end if
          call AddH2 (genLoc, atomic, sol, tbMod, ioLoc)
          call DiagHamiltonian (ioLoc, genLoc, atomic, sol)
!               if (genLoc%alter_dm) then
!                   call create_dm_spin_altered(eigenvec,eigenval)
!               endif
          call BuildDensity (atomic, sol)
          sol%buff%densityout = sol%density
          call CalcExcessCharges (genLoc, atomic, sol)
          call CalcDipoles (genLoc, atomic, sol, tbMod)
          call ComputeMagneticMoment (genLoc, atomic, sol, ioLoc)
          if (ioLoc%Verbosity >= k_highVerbos) then
            if (( .not. genLoc%compElec) .and. (genLoc%electrostatics == k_electrostaticsMultipoles)) then
              call initQvs (atomic, genLoc, sol, tbMod, sol%buff%densityout)
            end if
!
            call MatrixCeaApbB (sol%h2, sol%h, sol%hin, k_cOne,-k_cOne, ioLoc)
            if (genLoc%spin) then
              call PrintMatrixBlocks (sol%h, labels, ioLoc, .false., .not. genLoc%collinear)
              call PrintMatrixBlocks (sol%h2, labelsH2, ioLoc, .false., .not. genLoc%collinear)
            else
              call PrintMatrix (sol%h, "H: ", ioLoc)
              call PrintMatrix (sol%eigenvecs, "Eigenvectors: ", ioLoc)
            end if
            call PrintOccupationNumbers (genLoc, sol, ioLoc)
            write (ioLoc%uout, "(a,f16.8)") "chemical potential: ", genLoc%electronicMu
            write (ioLoc%uout, '(a,f16.8)') "Entropy term: ", sol%electronicEntropy
            do i = 1, atomic%atoms%natoms
              if (genLoc%electrostatics == k_electrostaticsMultipoles) then
                call PrintQlmR (i, genLoc, atomic, sol, tbMod, ioLoc, sol%buff%densityin)
                call PrintVlmR (i, genLoc, atomic, sol, tbMod, ioLoc, sol%buff%densityin)
              end if
              call PrintAtomChargeAnalysis (i, atomic, sol, genLoc, ioLoc)
              call PrintAtomMatrix (i, atomic, sol%h, "H", ioLoc, .false.)
              call PrintAtomMatrix (i, atomic, sol%hin, "Hin", ioLoc, .false.)
              call PrintAtomMatrix (i, atomic, sol%h2, "H2", ioLoc, .false.)
              call PrintAtomMatrix (i, atomic, sol%rho, "Density", ioLoc, .false.)
            end do
            call PrintCharges (genLoc, atomic, ioLoc)
            call PrintDipoles (atomic, ioLoc)
            if (genLoc%spin) call PrintMagneticMoment (atomic, sol, .true., ioLoc)
          end if
!
          ierr = - 1
          nmix = genLoc%scfMixn
          do while ((genLoc%scfMixn >=  1) .and. (ierr /= 0))
            call InitMix (sol%buff%dins, sol%buff%douts, sol%buff%res, sol%buff%densityin, sol%buff%densityout, genLoc%scfMixn)
            call MixDensity (sol%buff%dins, sol%buff%douts, sol%buff%res, sol%buff%densitynext, &
              residual, dmax, genLoc%scfMix, n+m, &
              genLoc%scfMixn, nit, ierr,ioLoc)
            if (ierr /= 0) then
              genLoc%scfMixn = genLoc%scfMixn - 1
              call error ("Singularity in mixing matrix, no of iterations mixed reduced by one ", sMyName, .false., ioLoc)
            end if
          end do
          if (ierr /= 0) then
            call error ("Singularity in mixing matrix, iterations to mix reduced up to 2", sMyName, .true., ioLoc)
          end if
          genLoc%scfMixn = nmix
          sol%buff%densityin = sol%buff%densitynext
          sol%density = sol%buff%densitynext
          call CopyMatrix (sol%h, sol%hin, ioLoc)
!               if (ioLoc%Verbosity >=k_highVerbos) then
!                   call Print_density(densityin,"density in")
!                   call Print_density(densityout,"density out")
!                   call Print_density(densitynext,"density next")
!               endif
!
          if (ioLoc%Verbosity >= k_highVerbos) then
            call ZeroForces (atomic)
            call RepulsiveForces (genLoc, atomic%atoms, tbMod)
            call electronicForces (atomic, genLoc, tbMod, sol, ioLoc)
            call ScfForces (genLoc, atomic, sol, tbMod, ioLoc)
            sol%density = sol%buff%densitynext
            call PrintForces (atomic%atoms, ioLoc)
            ee = ElectronicEnergy (genLoc, sol, ioLoc)
            re = RepulsiveEnergy (genLoc, atomic%atoms, tbMod)
            write (ioLoc%uout, '(a)') "Energy"
            write (ioLoc%uout, '(a,f16.8)') "Electronic: ", ee
            write (ioLoc%uout, '(a,f16.8)') " Repulsive: ", re
            scfe = ScfEnergy (genLoc, atomic, sol, tbMod, ioLoc)
            sol%density = sol%buff%densitynext
            write (ioLoc%uout, '(a,f16.8)') "       -TS: ", sol%electronicEntropy
            write (ioLoc%uout, '(a,f16.8)') "       SCF: ", scfe
            write (ioLoc%uout, '(a,f16.8)') "     Total: ", ee + re + scfe
          end if
          write (ioLoc%uout, '(a,i5,f16.8,f16.8,f16.8,f16.8,f16.8)') "SCFReport ", nit, ee + re + scfe, residual, dmax, real &
         & (MatrixTrace(sol%rho, ioLoc)), genLoc%electronicMu
          if (dmax < genLoc%scftol) exit
        end do
!
        if (ioLoc%uout /= 6) then
          if (nit > genLoc%maxscf) then
            write (6, '(a,i0,a,ES12.4)') "Warning: it did not converge after ", genLoc%maxscf, " the tolerance reached is ", dmax
            genLoc%lIsSCFConverged = .false.
          else
            write (6, '(a,i0,a,ES12.4)') "converged in ", nit, " iterations up to ", dmax
          end if
        end if
        if (nit > genLoc%maxscf) then
          write (ioLoc%uout, '(a,i0,a,ES12.4)') "Warning: it did not converge after ", nit, " the tolerance reached is ", dmax
          genLoc%lIsSCFConverged = .false.
        else
          write (ioLoc%uout, '(a,i0,a,ES12.4)') "converged in ", nit, " iterations up to ", dmax
        end if
!
!
!           ! calculate the forces
        if (( .not. genLoc%compElec) .and. (genLoc%electrostatics == k_electrostaticsMultipoles)) then
          call initQvs (atomic, genLoc, sol, tbMod, sol%density)
        end if
!
        call CalcExcessCharges (genLoc, atomic, sol)
        call CalcDipoles (genLoc, atomic, sol, tbMod)
        call ComputeMagneticMoment (genLoc, atomic, sol, ioLoc)
        call ZeroForces (atomic)
        call RepulsiveForces (genLoc, atomic%atoms, tbMod)
        call electronicForces (atomic, genLoc, tbMod, sol, ioLoc)
        call ScfForces (genLoc, atomic, sol, tbMod, ioLoc)
!             call Print_eigens(eigenval,eigenvec,555,.false.)
!             call write_density_matrix("rho.bin",rho%a,rho%dim)
        if (ioLoc%Verbosity >= k_mediumVerbos) then
          trace = MatrixTrace (sol%rho, ioLoc)
          write (saux, '(a,"(",f0.4,1x,f0.4,"i)")') "Density matrix, Trace= ", trace
          call PrintMatrix (sol%rho, trim(saux), ioLoc)
        end if
      end select
    else
      call BuildHamiltonian (ioLoc, genLoc, atomic, tbMod, sol)
      call AddBias (1.0_k_pr, atomic, sol)
      call DiagHamiltonian (ioLoc, genLoc, atomic, sol)
      call BuildDensity (atomic, sol)
      if (ioLoc%Verbosity >= k_mediumVerbos) then
        call PrintMatrix (sol%h, "Hamiltonian Matrix:", ioLoc)
        call PrintVectorA (sol%eigenvals, "Eigenvalues", .false., .true., ioLoc)
        call PrintMatrix (sol%eigenvecs, "Eigenvectors", ioLoc)
        trace = MatrixTrace (sol%rho, ioLoc)
        write (saux, '(a,"(",f0.4,1x,f0.4,"i)")') "Density matrix, Trace= ", trace
        call PrintMatrix (sol%rho, trim(saux), ioLoc)
      end if
      call ZeroForces (atomic)
      call RepulsiveForces (genLoc, atomic%atoms, tbMod)
      call electronicForces (atomic, genLoc, tbMod, sol, ioLoc)
      call CalcExcessCharges (genLoc, atomic, sol)
      call CalcDipoles (genLoc, atomic, sol, tbMod)
      call ComputeMagneticMoment (genLoc, atomic, sol, ioLoc)
!         call Print_eigens(eigenval,eigenvec,555,.false.)
    end if
  end subroutine FullScf
!
!
!> \brief adds the \f$ {\mathbf H}_2 \f$ to the Hamiltonian
!> \author Alin M Elena
!> \date 08/11/07, 14:02:54
!> \param io type(ioType) contains all the info about I/O files
!> \param gen type(generalType) contains the info needed by the program to k_run
!> \param atomic type(atomicxType) contains all info about the atoms and basis set and some parameters
!> \param sol type(solutionType) contains information about the solution space
!> \param tb type(modelType) contains information about the tight binding model parameters
  subroutine AddH2 (gen, atomic, sol, tb, io)
    character (len=*), parameter :: myname = 'AddH2'
    type (ioType), intent (inout) :: io
    type (generalType), intent (inout) :: gen
    type (atomicxType), intent (inout) :: atomic
    type (solutionType), intent (inout) :: sol
    type (modelType), intent (inout) :: tb
!
    integer :: i, k
!
    select case (gen%scfType)
    case (k_scfTbuj)
      select case (gen%electrostatics)
      case (k_electrostaticsPoint)
        call BuildPotential (gen, atomic, sol)
        do k = 1, atomic%atoms%nscf
          i = atomic%atoms%scf(k)
          call AddUJ (i, gen, atomic, sol, tb, io)
          call AddElectrostaticsPoints (i, gen, atomic, sol, tb, io)
        end do
      case (k_electrostaticsMultipoles)
        if (io%Verbosity >= k_highVerbos) then
          write (io%uout, "(a)") "Multipoles increments"
        end if
        do k = 1, atomic%atoms%nscf
          i = atomic%atoms%scf(k)
          call AddUJ (i, gen, atomic, sol, tb, io)
          call AddElectrostaticsMultipolesSpin (i, gen, atomic, sol, tb, io)
        end do
      end select
    case (k_scfTBu)
      select case (gen%electrostatics)
      case (k_electrostaticsPoint)
        call BuildPotential (gen, atomic, sol)
        do k = 1, atomic%atoms%nscf
          i = atomic%atoms%scf(k)
          call AddU (i, gen, atomic, sol, tb, io)
          call AddElectrostaticsPoints (i, gen, atomic, sol, tb, io)
        end do
      case (k_electrostaticsMultipoles)
        if (io%Verbosity >= k_highVerbos) then
          write (io%uout, "(a)") "Multipoles increments"
        end if
        do k = 1, atomic%atoms%nscf
          i = atomic%atoms%scf(k)
          call AddU (i, gen, atomic, sol, tb, io)
          call AddElectrostaticsMultipolesSpin (i, gen, atomic, sol, tb, io)
        end do
      end select
    case (k_scfTBUO)
      select case (gen%electrostatics)
      case (k_electrostaticsPoint)
        call BuildPotential (gen, atomic, sol)
        do k = 1, atomic%atoms%nscf
          i = atomic%atoms%scf(k)
          call AddUO (i, gen, atomic, sol, tb, io)
          call AddElectrostaticsPoints (i, gen, atomic, sol, tb, io)
        end do
      case (k_electrostaticsMultipoles)
        if (io%Verbosity >= k_highVerbos) then
          write (io%uout, "(a)") "Multipoles increments"
        end if
        do k = 1, atomic%atoms%nscf
          i = atomic%atoms%scf(k)
          call AddUO (i, gen, atomic, sol, tb, io)
          call AddElectrostaticsMultipolesSpin (i, gen, atomic, sol, tb, io)
        end do
      end select
    case (k_scfTBujo)
      select case (gen%electrostatics)
      case (k_electrostaticsPoint)
        call BuildPotential (gen, atomic, sol)
        do k = 1, atomic%atoms%nscf
          i = atomic%atoms%scf(k)
          call AddUJO (i, gen, atomic, sol, tb, io)
          call AddElectrostaticsPoints (i, gen, atomic, sol, tb, io)
        end do
      case (k_electrostaticsMultipoles)
        if (io%Verbosity >= k_highVerbos) then
          write (io%uout, "(a)") "Multipoles increments"
        end if
        do k = 1, atomic%atoms%nscf
          i = atomic%atoms%scf(k)
          call AddUJO (i, gen, atomic, sol, tb, io)
          call AddElectrostaticsMultipolesSpin (i, gen, atomic, sol, tb, io)
        end do
      end select
    end select
!
  end subroutine AddH2
!
!> \brief computes the electron numbers for an atom
!> \details the total number and in each spin channel
!> \author Alin M Elena
!> \date 08/11/07, 15:31:01
!> \param at integer the atom
!> \param q0,q0up,q0down reals electron numbers total, spin up and spin down
!> \param atomic type(atomicxType) contains all info about the atoms and basis set and some parameters
!> \param sol type(solutionType) contains information about the solution space
  subroutine SCFChargeNumbersSpin (at, q0, q0up, q0down, atomic, sol)
    character (len=*), parameter :: myname = "ScfChargeNumbersSpin"
    real (k_pr), intent (inout) :: q0
    real (k_pr), intent (inout) :: q0up, q0down
    integer, intent (in) :: at
    type (solutionType), intent (in) :: sol
    type (atomicxType), intent (in) :: atomic
    integer :: from, to, m
!
!
    q0up = 0.0_k_pr
    q0down = 0.0_k_pr
! spin down
    m = atomic%basis%norbitals * (atomic%basis%norbitals-1) / 2
    from = m + atomic%atoms%orbs(at, 1)
    to = - 1 + from + atomic%species%norbs(atomic%atoms%sp(at)) / 2
    q0down = sum (sol%density(from:to))
!spin up
    from = m + atomic%atoms%orbs(at, 1) + atomic%basis%norbitals / 2
    to = - 1 + from + atomic%species%norbs(atomic%atoms%sp(at)) / 2
    q0up = sum (sol%density(from:to))
! total charge
    q0 = q0down + q0up
  end subroutine SCFChargeNumbersSpin
!
!
!
!> \brief computes the electron numbers for an atom in the orbital with angular momentum l
!> \details the total number and in each spin channel
!> \author Alin M Elena
!> \date 08/11/07, 15:31:01
!> \param at integer the atom
!> \param l integer the angular momentum of the orbital
!> \param q0,q0up,q0down reals electron numbers total, spin up and spin down
!> \param atomic type(atomicxType) contains all info about the atoms and basis set and some parameters
!> \param sol type(solutionType) contains information about the solution space
  subroutine SCFChargeNumbersLSpin (at, l, q0, q0up, q0down, atomic, sol)
    character (len=*), parameter :: myname = "ScfChargeNumbersLSpin"
    real (k_pr), intent (inout) :: q0
    real (k_pr), intent (inout) :: q0up, q0down
    integer, intent (in) :: at, l
    type (solutionType), intent (in) :: sol
    type (atomicxType), intent (in) :: atomic
    integer :: from, to, m, j
!
    q0up = 0.0_k_pr
    q0down = 0.0_k_pr
    j = l * l
! spin down
    m = atomic%atoms%orbs(at, 1) + atomic%basis%norbitals * (atomic%basis%norbitals-1) / 2
    from = m + j
    to = - 1 + from + 2 * l + 1
    q0down = sum (sol%density(from:to))
!
!spin up
    from = m + atomic%basis%norbitals / 2 + j
    to = - 1 + from + 2 * l + 1
    q0up = sum (sol%density(from:to))
! total charge
    q0 = q0down + q0up
  end subroutine SCFChargeNumbersLSpin
!
!
!
!
!
!> \brief computes the electron numbers for a spinless atom
!> \author Alin M Elena
!> \date 08/11/07, 15:31:01
!> \param at integer the atom
!> \param q0 real electron numbers total
!> \param atomic type(atomicxType) contains all info about the atoms and basis set and some parameters
!> \param sol type(solutionType) contains information about the solution space
  subroutine SCFChargeNumbersSpinLess (at, q0, atomic, sol)
    character (len=*), parameter :: myname = "ScfChargeNumbersSpinLess"
    real (k_pr), intent (inout) :: q0
    integer, intent (in) :: at
    type (solutionType), intent (in) :: sol
    type (atomicxType), intent (in) :: atomic
    integer :: from, to, m
!
    q0 = 0.0_k_pr
    m = atomic%basis%norbitals * (atomic%basis%norbitals-1) / 2
    from = m + atomic%atoms%orbs(at, 1)
    to = - 1 + m + atomic%atoms%orbs(at, 1) + atomic%species%norbs(atomic%atoms%sp(at))
    q0 = sum (sol%density(from:to))
  end subroutine SCFChargeNumbersSpinLess
!
!> \brief computes the electron numbers for a spinless atom on the orbital with angular momentum l
!> \author Alin M Elena
!> \date 08/11/07, 15:31:01
!> \param at integer the atom
!> \param l integer the angular momentum of the orbital
!> \param q0 real electron numbers total
!> \param atomic type(atomicxType) contains all info about the atoms and basis set and some parameters
!> \param sol type(solutionType) contains information about the solution space
  subroutine SCFChargeNumbersLSpinLess (at, l, q0, atomic, sol)
    character (len=*), parameter :: myname = "ScfChargeNumbersLSpinLess"
    real (k_pr), intent (inout) :: q0
    integer, intent (in) :: at, l
    type (solutionType), intent (in) :: sol
    type (atomicxType), intent (in) :: atomic
    integer :: from, to, m, j
!
    q0 = 0.0_k_pr
    j = l * l
    m = atomic%atoms%orbs(at, 1) + atomic%basis%norbitals * (atomic%basis%norbitals-1) / 2
    from = m + j
    to = - 1 + from + 2 * l + 1
    q0 = sum (sol%density(from:to))
  end subroutine SCFChargeNumbersLSpinLess
!
!
!> \brief computes the scf energy
!> \author Alin M Elena
!> \date 08/11/07, 23:13:45
!> \param io type(ioType) contains all the info about I/O files
!> \param gen type(generalType) contains the info needed by the program to run
!> \param atomic type(atomicxType) contains all info about the atoms and basis set and some parameters
!> \param tb type(modelType) contains information about the tight binding model parameters
!> \param sol type(solutionType) contains information about the solution space
  real (k_pr) function ScfEnergy (gen, atomic, sol, tb, io)
    character (len=*), parameter :: myname = 'ScfEnergy'
    type (ioType), intent (inout) :: io
    type (generalType), intent (inout) :: gen
    type (atomicxType), intent (inout) :: atomic
    type (solutionType), intent (inout) :: sol
    type (modelType), intent (inout) :: tb
    integer :: i, k, mp, j
    real (k_pr) :: scfe, scfx !,el_en
! +U variables
    integer :: l1, l2, l3, l4, m1, m2, m3, m4, o1, o2, o3, o4, sp, shift, m, n
    real (k_pr) :: v_tmp, elecEn, aux
    real (k_pr) :: q0, q0up, q0down
!-------------------------------------------------!
!
    scfe = 0.0_k_pr
    elecEn = 0.0_k_pr
    scfx = 0.0_k_pr
    sol%density = 0.0_k_pr
    call BuildDensity (atomic, sol)
    select case (gen%scfType)
    case (k_scfTbuj)
      scfe = 0.0_k_pr
      do k = 1, atomic%atoms%nscf
        i = atomic%atoms%scf(k)
        call SCFChargeNumbers (i, q0, q0up, q0down, atomic, sol)
        scfe = scfe + atomic%species%ulocal(atomic%atoms%sp(i), 1) * q0 * q0
        scfx = scfx - atomic%species%jlocal(atomic%atoms%sp(i), 1) * (q0up*q0up+q0down*q0down)
      end do
      scfe = scfe * 0.5_k_pr !*k_e2/(4.0_k_pr*k_pi*k_epsilon0)
      scfx = scfx * 0.5_k_pr !*k_e2/(4.0_k_pr*k_pi*k_epsilon0)
      if (io%Verbosity >= k_highVerbos) then
        write (io%uout, '(a,f16.8)') " SCF energy from U: ", scfe
        write (io%uout, '(a,f16.8)') " SCF energy from J: ", scfx
      end if
      scfe = scfe + scfx
    case (k_scfTBu)
      scfe = 0.0_k_pr
      do k = 1, atomic%atoms%nscf
        i = atomic%atoms%scf(k)
        call SCFChargeNumbers (i, q0, atomic, sol)
        scfe = scfe + atomic%species%ulocal(atomic%atoms%sp(i), 1) * q0 * q0
      end do
      scfe = scfe * 0.5_k_pr
      if (io%Verbosity >= k_highVerbos) then
        write (io%uout, '(a,f16.8)') " SCF energy from U: ", scfe
      end if
    case (k_scfTBUO)
      do k = 1, atomic%atoms%nscf
        i = atomic%atoms%scf(k)
        do j = 1, atomic%species%ulocal(atomic%atoms%sp(i), 0)
          call SCFChargeNumbers (i, j-1, q0, atomic, sol)
          m1 = atomic%atoms%orbs(i, 1) + (j-1) * (j-1)
          m2 = m1 + 2 * j - 2
          do o1 = m1, m2
            scfe = scfe + atomic%species%ulocal(atomic%atoms%sp(i), j) * q0 * q0
          end do
        end do
      end do
      scfe = scfe * 0.5_k_pr
      if (io%Verbosity >= k_highVerbos) then
        write (io%uout, '(a,f16.8)') " SCF energy from U: ", scfe
      end if
    case (k_scfTBujo)
      do k = 1, atomic%atoms%nscf
        i = atomic%atoms%scf(k)
        shift = atomic%species%ulocal(atomic%atoms%sp(i), 0)
        do j = 1, atomic%species%ulocal(atomic%atoms%sp(i), 0)
          call SCFChargeNumbers (i, j-1, q0, q0down, q0up, atomic, sol)
          m1 = atomic%atoms%orbs(i, 1) + (j-1) * (j-1)
          m2 = m1 + 2 * j - 2
          do o1 = m1, m2
            scfe = scfe + atomic%species%ulocal(atomic%atoms%sp(i), j) * q0down * q0down
            scfe = scfe + atomic%species%ulocal(atomic%atoms%sp(i), j+shift) * q0up * q0up
            scfx = scfx - atomic%species%jlocal(atomic%atoms%sp(i), j) * q0up * q0up
            scfx = scfx - atomic%species%jlocal(atomic%atoms%sp(i), j+shift) * q0down * q0down
          end do
        end do
      end do
      scfe = scfe * 0.5_k_pr
      scfx = scfx * 0.5_k_pr
      if (io%Verbosity >= k_highVerbos) then
        write (io%uout, '(a,f16.8)') " SCF energy from U: ", scfe
        write (io%uout, '(a,f16.8)') " SCF energy from J: ", scfx
      end if
      scfe = scfe + scfx
    end select
!
    select case (gen%electrostatics)
    case (k_electrostaticsPoint)
      call BuildPotential (gen, atomic, sol)
      do k = 1, atomic%atoms%nscf
        i = atomic%atoms%scf(k)
        elecEn = elecEn + 0.5_k_pr * charge (i, gen, atomic, sol) * sol%potential(i)
      end do
    case (k_electrostaticsMultipoles)
      do k = 1, atomic%atoms%nscf
        i = atomic%atoms%scf(k)
        aux = 0.0_k_pr
        do l1 = 0, 2 * GetLmax (atomic%atoms%sp(i), atomic%speciesBasis, atomic%species)
          do m1 = - l1, l1
            aux = aux + qlmR (i, l1, m1, gen, sol, atomic, tb, sol%density) * vlmR (i, l1, m1, gen, sol, atomic, tb, sol%density)
          end do
        end do
        elecEn = elecEn + 0.5_k_pr * aux !*k_e2/(4.0_k_pr*k_pi*k_epsilon0)
      end do
    end select
    if (io%Verbosity >= k_highVerbos) then
      write (io%uout, '(a,f16.8)') "SCF Electrostatics: ", elecEn
    end if
    ScfEnergy = scfe + elecEn
  end function ScfEnergy
!> \brief computes the scf contribution to the forces
!> \author Alin M Elena
!> \date 08/11/07, 23:14:30
!> \param io type(ioType) contains all the info about I/O files
!> \param gen type(generalType) contains the info needed by the program to run
!> \param atomic type(atomicxType) contains all info about the atoms and basis set and some parameters
!> \param sol type(solutionType) contains information about the solution space
!> \param tb type(modelType) contains information about the tight binding model parameters
  subroutine ScfForces (gen, atomic, sol, tb, io)
    character (len=*), parameter :: myname = 'ScfForces'
    type (ioType), intent (inout) :: io
    type (generalType), intent (inout) :: gen
    type (atomicxType), intent (inout) :: atomic
    type (solutionType), intent (inout) :: sol
    type (modelType), intent (inout) :: tb
    integer :: i, m, n, li, j, mi !,j,mpp,l,m
    real (k_pr) :: q
    integer :: lm, k
    real (k_pr) :: aux, sx, sy, sz
!
    select case (gen%electrostatics)
    case (k_electrostaticsPoint)
      sol%density = 0.0_k_pr
      call BuildDensity (atomic, sol)
      call BuildField (gen, atomic, sol)
      do k = 1, atomic%atoms%nmoving
        i = atomic%atoms%moving(k)
        q = charge (i, gen, atomic, sol)
        atomic%atoms%fx (i) = atomic%atoms%fx(i) + q * sol%field(i, 1)
        atomic%atoms%fy (i) = atomic%atoms%fy(i) + q * sol%field(i, 2)
        atomic%atoms%fz (i) = atomic%atoms%fz(i) + q * sol%field(i, 3)
      end do
    case (k_electrostaticsMultipoles)
      n = atomic%basis%norbitals
      m = n * (n-1) / 2
      call BuildDensity (atomic, sol)
      do k = 1, atomic%atoms%nmoving
        i = atomic%atoms%moving(k)
        do li = 0, 2 * GetLmax (atomic%atoms%sp(i), atomic%speciesBasis, atomic%species)
          aux = (2.0_k_pr*li+3.0_k_pr) * Sqrt (4.0_k_pr*k_pi/3.0_k_pr)!*k_e2/(4.0_k_pr*k_pi*k_epsilon0)
          sx = 0.0_k_pr
          sy = 0.0_k_pr
          sz = 0.0_k_pr
          do mi = - li, li
            sx = sx + fip (i, li, mi, 1, gen, sol, atomic, tb, sol%density) * qlmR (i, li, mi, gen, sol, atomic, tb, sol%density)
            sy = sy + fip (i, li, mi,-1, gen, sol, atomic, tb, sol%density) * qlmR (i, li, mi, gen, sol, atomic, tb, sol%density)
            sz = sz + fip (i, li, mi, 0, gen, sol, atomic, tb, sol%density) * qlmR (i, li, mi, gen, sol, atomic, tb, sol%density)
          end do
          atomic%atoms%fx (i) = atomic%atoms%fx(i) - sx * aux
          atomic%atoms%fy (i) = atomic%atoms%fy(i) - sy * aux
          atomic%atoms%fz (i) = atomic%atoms%fz(i) - sz * aux
        end do
      end do
    end select
  end subroutine ScfForces
!
!
  subroutine AddUJ (i, gen, atomic, sol, tb, io)
    character (len=*), parameter :: myname = 'AddUJ'
    type (ioType), intent (inout) :: io
    type (generalType), intent (inout) :: gen
    type (atomicxType), intent (inout) :: atomic
    type (solutionType), intent (inout) :: sol
    type (modelType), intent (inout) :: tb
    integer, intent (inout) :: i
!
    real (k_pr) :: rAddAcc, rTmp, hij, hijf, hijd
    integer :: m, n, o2, o3, o1, shift
    real (k_pr) :: q0, q0up, q0down, aux, udq, uuq, elec, auxu
!
!
    n = sol%h%dim
    m = n * (n-1) / 2
    shift = n / 2
    q0 = 0.0_k_pr
    q0up = 0.0_k_pr
    q0down = 0.0_k_pr
    rTmp = 0.0_k_pr
    rAddAcc = 0.0_k_pr
!
    call SCFChargeNumbers (i, q0, q0up, q0down, atomic, sol)
!! ! spin down
    udq = atomic%species%ulocal(atomic%atoms%sp(i), 1) * q0
    rAddAcc = - atomic%species%jlocal(atomic%atoms%sp(i), 1) * q0down ! spin up
    rTmp = - atomic%species%jlocal(atomic%atoms%sp(i), 1) * q0up
    if (io%Verbosity >= k_highVerbos) then
      write (io%uout, '(a,i5,a,i5,a,a2)') " Atom: ", i, "  specie ", atomic%atoms%sp(i), " element ", symbol &
     & (atomic%species%z(atomic%atoms%sp(i)))
      write (io%uout, '(a,f16.8)') " U*dQ: ", udq
      write (io%uout, '(a,f16.8,a,f16.8)') "J*dNd: ", rAddAcc, "  J*dNu", rTmp
    end if
    do o1 = 1, atomic%species%norbs(atomic%atoms%sp(i)) / 2
      o2 = atomic%atoms%orbs(i, o1)
      o3 = o2 + shift
!! !spin down
      hij = sol%h%a(o2, o2) + rAddAcc + udq
      if (Abs(hij) >= gen%hElementThreshold) then
        call SpmPut (sol%h, o2, o2, cmplx(hij, 0.0_k_pr, k_pr))
      end if
!! !spin up
      hij = sol%h%a(o3, o3) + rTmp + udq
      if (Abs(hij) >= gen%hElementThreshold) then
        call SpmPut (sol%h, o3, o3, cmplx(hij, 0.0_k_pr, k_pr))
      end if
    end do
  end subroutine AddUJ
!
  subroutine AddU (i, gen, atomic, sol, tb, io)
    character (len=*), parameter :: myname = 'AddU'
    type (ioType), intent (inout) :: io
    type (generalType), intent (inout) :: gen
    type (atomicxType), intent (inout) :: atomic
    type (solutionType), intent (inout) :: sol
    type (modelType), intent (inout) :: tb
    integer, intent (inout) :: i
!
    real (k_pr) :: hij, udq, q0
    integer :: o1, o2
!
    call SCFChargeNumbers (i, q0, atomic, sol)
    udq = atomic%species%ulocal(atomic%atoms%sp(i), 1) * q0
    if (io%Verbosity >= k_highVerbos) then
      write (io%uout, '(a,i5,a,i5,a,a2)') " Atom: ", i, "  specie ", atomic%atoms%sp(i), " element ", symbol &
     & (atomic%species%z(atomic%atoms%sp(i)))
      write (io%uout, '(a,f16.8)') " U*dQ: ", udq
    end if
    do o1 = 1, atomic%species%norbs(atomic%atoms%sp(i))
      o2 = atomic%atoms%orbs(i, o1)
      hij = sol%h%a(o2, o2) + udq
      if (Abs(hij) >= gen%hElementThreshold) then
        call SpmPut (sol%h, o2, o2, cmplx(hij, 0.0_k_pr, k_pr))
      end if
    end do
!
  end subroutine AddU
!
  subroutine AddUJO (i, gen, atomic, sol, tb, io)
    character (len=*), parameter :: myname = 'AddUJO'
    type (ioType), intent (inout) :: io
    type (generalType), intent (inout) :: gen
    type (atomicxType), intent (inout) :: atomic
    type (solutionType), intent (inout) :: sol
    type (modelType), intent (inout) :: tb
    integer, intent (inout) :: i
!
    real (k_pr) :: rAddAcc, rTmp, hij, hijf, hijd
    integer :: m, n, o2, o3, o1, shift, j, m1, m2
    real (k_pr) :: q0, q0up, q0down, aux, udq, uuq, elec, auxu
!
!
    n = sol%h%dim
    m = n * (n-1) / 2
    aux = n / 2
    q0 = 0.0_k_pr
    q0up = 0.0_k_pr
    q0down = 0.0_k_pr
    rTmp = 0.0_k_pr
    rAddAcc = 0.0_k_pr
!
    shift = atomic%species%ulocal(atomic%atoms%sp(i), 0)
    if (io%Verbosity >= k_highVerbos) then
      write (io%uout, '(a,i5,a,i5,a,a2)') " Atom: ", i, "  specie ", atomic%atoms%sp(i), " element ", symbol &
     & (atomic%species%z(atomic%atoms%sp(i)))
    end if
    do j = 1, atomic%species%ulocal(atomic%atoms%sp(i), 0)
      call SCFChargeNumbers (i, j-1, q0, q0down, q0up, atomic, sol)
      udq = atomic%species%ulocal(atomic%atoms%sp(i), j) * q0down
      uuq = atomic%species%ulocal(atomic%atoms%sp(i), j+shift) * q0up
      rAddAcc = - atomic%species%jlocal(atomic%atoms%sp(i), j+shift) * q0down ! spin up
      rTmp = - atomic%species%jlocal(atomic%atoms%sp(i), j) * q0up
      if (io%Verbosity >= k_highVerbos) then
        write (io%uout, '(a,i0,a,f16.8,a1,f16.8,a1,f16.8,a1)') "l=", j - 1, " U*dQ (spin down): ", udq, "(", &
       & atomic%species%ulocal(atomic%atoms%sp(i), j), "*", q0down, ")"
        write (io%uout, '(a,i0,a,f16.8,a1,f16.8,a1,f16.8,a1)') "l=", j - 1, " U*dQ (spin up): ", uuq, "(", &
       & atomic%species%ulocal(atomic%atoms%sp(i), j+shift), "*", q0up, ")"
        write (io%uout, '(a,i0,a,f16.8,a1,f16.8,a1,f16.8,a1)') "l=", j - 1, " J*dQup (spin down): ", rTmp, "(", &
       & atomic%species%jlocal(atomic%atoms%sp(i), j), "*", q0up, ")"
        write (io%uout, '(a,i0,a,f16.8,a1,f16.8,a1,f16.8,a1)') "l=", j - 1, " J*dQdown (spin up): ", rAddAcc, "(", &
       & atomic%species%jlocal(atomic%atoms%sp(i), j+shift), "*", q0down, ")"
      end if
      m1 = atomic%atoms%orbs(i, 1) + (j-1) * (j-1)
      m2 = m1 + 2 * j - 2
      do o1 = m1, m2
        hij = sol%h%a(o1, o1) + udq + rTmp
        if (Abs(hij) >= gen%hElementThreshold) then
          call SpmPut (sol%h, o1, o1, cmplx(hij, 0.0_k_pr, k_pr))
        end if
        o2 = o1 + aux
        hij = sol%h%a(o2, o2) + uuq + rAddAcc
        if (Abs(hij) >= gen%hElementThreshold) then
          call SpmPut (sol%h, o2, o2, cmplx(hij, 0.0_k_pr, k_pr))
        end if
      end do
    end do
  end subroutine AddUJO
!
  subroutine AddUO (i, gen, atomic, sol, tb, io)
    character (len=*), parameter :: myname = 'AddUO'
    type (ioType), intent (inout) :: io
    type (generalType), intent (inout) :: gen
    type (atomicxType), intent (inout) :: atomic
    type (solutionType), intent (inout) :: sol
    type (modelType), intent (inout) :: tb
    integer, intent (inout) :: i
!
    real (k_pr) :: hij, udq, q0
    integer :: o1, j, m1, m2
!
    if (io%Verbosity >= k_highVerbos) then
      write (io%uout, '(a,i5,a,i5,a,a2)') " Atom: ", i, "  specie ", atomic%atoms%sp(i), " element ", symbol &
     & (atomic%species%z(atomic%atoms%sp(i)))
    end if
    do j = 1, atomic%species%ulocal(atomic%atoms%sp(i), 0)
      call SCFChargeNumbers (i, j-1, q0, atomic, sol)
      udq = atomic%species%ulocal(atomic%atoms%sp(i), j) * q0
      if (io%Verbosity >= k_highVerbos) then
        write (io%uout, '(a,i0,a,f16.8,a1,f16.8,a1,f16.8,a1)') "l=", j - 1, " U*dQ: ", udq, "(", &
       & atomic%species%ulocal(atomic%atoms%sp(i), j), "*", q0, ")"
      end if
      m1 = atomic%atoms%orbs(i, 1) + (j-1) * (j-1)
      m2 = m1 + 2 * j - 2
      do o1 = m1, m2
        hij = sol%h%a(o1, o1) + udq
        if (Abs(hij) >= gen%hElementThreshold) then
          call SpmPut (sol%h, o1, o1, cmplx(hij, 0.0_k_pr, k_pr))
        end if
      end do
    end do
!
  end subroutine AddUO
!
!
  subroutine AddElectrostaticsPoints (i, gen, atomic, sol, tb, io)
    character (len=*), parameter :: myname = 'AddElectrostaticsPoints'
    type (ioType), intent (inout) :: io
    type (generalType), intent (inout) :: gen
    type (atomicxType), intent (inout) :: atomic
    type (solutionType), intent (inout) :: sol
    type (modelType), intent (inout) :: tb
    integer, intent (inout) :: i
!
    integer :: o1
    real (k_pr) :: hij
!
    if (io%Verbosity >= k_highVerbos) then
      write (io%uout, '(a,i5,a,i5,a,a2)') " Atom: ", i, "  specie ", atomic%atoms%sp(i), " element ", symbol &
     & (atomic%species%z(atomic%atoms%sp(i)))
      write (io%uout, '(a,f16.8)') " Vrr': ", sol%potential(i)
    end if
    do o1 = 1, atomic%species%norbs(atomic%atoms%sp(i))
      hij = sol%h%a(atomic%atoms%orbs(i, o1), atomic%atoms%orbs(i, o1)) + sol%potential(i)
      call SpmPut (sol%h, atomic%atoms%orbs(i, o1), atomic%atoms%orbs(i, o1), cmplx(hij, 0.0_k_pr, k_pr))
    end do
!
  end subroutine AddElectrostaticsPoints
!
  subroutine AddElectrostaticsMultipolesSpin (i, gen, atomic, sol, tb, io)
    character (len=*), parameter :: myname = 'AddElectrostaticsMultipolesSpin'
    type (ioType), intent (inout) :: io
    type (generalType), intent (inout) :: gen
    type (atomicxType), intent (inout) :: atomic
    type (solutionType), intent (inout) :: sol
    type (modelType), intent (inout) :: tb
    integer, intent (inout) :: i
!
    integer :: sp, o1, o2, l1, m1, l2, m2
    integer :: o1u, o2u, l1u, m1u, l2u, m2u
    real (k_pr) :: aux, auxu, hij
!
    sp = atomic%atoms%sp(i)
    do o1 = 1, atomic%species%norbs(sp) / 2
      o1u = o1 + atomic%species%norbs(sp) / 2
      l1 = atomic%basis%orbitals(atomic%atoms%orbs(i, o1))%l
      m1 = atomic%basis%orbitals(atomic%atoms%orbs(i, o1))%m
      l1u = atomic%basis%orbitals(atomic%atoms%orbs(i, o1u))%l
      m1u = atomic%basis%orbitals(atomic%atoms%orbs(i, o1u))%m
      do o2 = 1, atomic%species%norbs(sp) / 2
        o2u = o2 + atomic%species%norbs(sp) / 2
        l2 = atomic%basis%orbitals(atomic%atoms%orbs(i, o2))%l
        m2 = atomic%basis%orbitals(atomic%atoms%orbs(i, o2))%m
        l2u = atomic%basis%orbitals(atomic%atoms%orbs(i, o2u))%l
        m2u = atomic%basis%orbitals(atomic%atoms%orbs(i, o2u))%m
        aux = hiujv (i, l1, m1, l2, m2, gen, sol, atomic, tb, sol%density)
        auxu = hiujv (i, l1u, m1u, l2u, m2u, gen, sol, atomic, tb, sol%density)
        if (io%Verbosity >= k_highVerbos) then
          if (Abs(aux) > epsilon(aux)) write (io%uout, "(a,i0,x,i0,x,i0,f12.8)") "d: ", i, o1, o2, aux
          write (io%uout, "(a,i0,x,i0,x,i0,f12.8)") "d: ", i, o1u, o2u, auxu
        end if
        hij = sol%h%a(atomic%atoms%orbs(i, o1), atomic%atoms%orbs(i, o2)) + aux
        call SpmPut (sol%h, atomic%atoms%orbs(i, o1), atomic%atoms%orbs(i, o2), cmplx(hij, 0.0_k_pr, k_pr))
        hij = sol%h%a(atomic%atoms%orbs(i, o1u), atomic%atoms%orbs(i, o2u)) + auxu
        call SpmPut (sol%h, atomic%atoms%orbs(i, o1u), atomic%atoms%orbs(i, o2u), cmplx(hij, 0.0_k_pr, k_pr))
      end do
!       if (gen%hasElectricField) then
!         if (io%Verbosity >= k_highVerbos) then
!           if (abs(aux)>epsilon(aux)) &
!             write(io%uout,"(a,i0,x,i0,x,f12.8)")"u: ",i,o1,aux
!         endif
!         aux=2.0_k_pr*atomic%atoms%chrg(i)*(atomic%atoms%x(i)*gen%E(1)+atomic%atoms%y(i)*gen%E(2)+atomic%atoms%z(i)*gen%E(3))
!         hij=sol%h%a(atomic%atoms%orbs(i,o1),atomic%atoms%orbs(i,o1))+aux
!         call spmPut(sol%h,atomic%atoms%orbs(i,o1),atomic%atoms%orbs(i,o1),cmplx(hij,0.0_k_pr,k_pr))
!         hij=sol%h%a(atomic%atoms%orbs(i,o1u),atomic%atoms%orbs(i,o1u))+aux
!         call SpmPut(sol%h,atomic%atoms%orbs(i,o1u),atomic%atoms%orbs(i,o1u),cmplx(hij,0.0_k_pr,k_pr))
!       endif
    end do
  end subroutine AddElectrostaticsMultipolesSpin
!
  subroutine AddElectrostaticsMultipolesSpinLess (i, gen, atomic, sol, tb, io)
    character (len=*), parameter :: myname = 'AddElectrostaticsMultipolesSpinLess'
    type (ioType), intent (inout) :: io
    type (generalType), intent (inout) :: gen
    type (atomicxType), intent (inout) :: atomic
    type (solutionType), intent (inout) :: sol
    type (modelType), intent (inout) :: tb
    integer, intent (inout) :: i
!
    integer :: sp, o1, o2, l1, m1, l2, m2
    real (k_pr) :: aux, hij
!
    sp = atomic%atoms%sp(i)
    do o1 = 1, atomic%species%norbs(sp)
      l1 = atomic%basis%orbitals(atomic%atoms%orbs(i, o1))%l
      m1 = atomic%basis%orbitals(atomic%atoms%orbs(i, o1))%m
      do o2 = 1, atomic%species%norbs(sp)
        l2 = atomic%basis%orbitals(atomic%atoms%orbs(i, o2))%l
        m2 = atomic%basis%orbitals(atomic%atoms%orbs(i, o2))%m
        aux = hiujv (i, l1, m1, l2, m2, gen, sol, atomic, tb, sol%density)
        if (io%Verbosity >= k_highVerbos) then
          if (Abs(aux) > epsilon(aux)) write (io%uout, "(a,i0,x,i0,x,i0,f12.8)") "u: ", i, o1, o2, aux
        end if
        hij = sol%h%a(atomic%atoms%orbs(i, o1), atomic%atoms%orbs(i, o2)) + aux
        call SpmPut (sol%h, atomic%atoms%orbs(i, o1), atomic%atoms%orbs(i, o2), cmplx(hij, 0.0_k_pr, k_pr))
      end do
!       if (gen%hasElectricField) then
!         if (io%Verbosity >= k_highVerbos) then
!           if (abs(aux)>epsilon(aux)) &
!             write(io%uout,"(a,i0,x,i0,x,f12.8)")"u: ",i,o1,aux
!         endif
!         aux=2.0_k_pr*atomic%atoms%chrg(i)*(atomic%atoms%x(i)*gen%E(1)+atomic%atoms%y(i)*gen%E(2)+atomic%atoms%z(i)*gen%E(3))
!         hij=sol%h%a(atomic%atoms%orbs(i,o1),atomic%atoms%orbs(i,o1))+aux
!         call spmPut(sol%h,atomic%atoms%orbs(i,o1),atomic%atoms%orbs(i,o1),cmplx(hij,0.0_k_pr,k_pr))
!       endif
    end do
  end subroutine AddElectrostaticsMultipolesSpinLess
!
end module m_SCF
!
