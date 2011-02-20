{-# LANGUAGE ForeignFunctionInterface #-}

-- | This module provides a fairly direct representation of the
-- SAM/BAM alignment format, along with an interface to read and write
-- alignments in this format.
-- 
-- The package is based on the C SamTools library available at
-- 
-- <http://samtools.sourceforge.net/>
-- 
-- and the SAM/BAM file format is described here
-- 
-- <http://samtools.sourceforge.net/SAM-1.3.pdf>
-- 
-- This package only reads existing alignment files generated by other
-- tools. The meaning of the various flags is actually determined by
-- the program that produced the alignment file.

module Bio.SamTools.Bam ( 
  -- | Target sequence sets
  HeaderSeq(..)
  , Header, nTargets, targetSeqs
  -- | SAM/BAM format alignments
  , Bam1
  , targetID, targetName, targetLen, position
  , isPaired, isProperPair, isUnmap, isMateUnmap, isReverse, isMateReverse
  , isRead1, isRead2, isSecondary, isQCFail, isDup
  , cigars, queryName, queryLength, querySeq
  , mateTargetID, mateTargetName, matePosition, insertSize
  -- | Reading SAM/BAM format files
  , InHandle, inHeader
  , openTamInFile, openTamInFileWithIndex, openBamInFile
  , closeInHandle
  , get1
  -- | Writing SAM/BAM format files
  , OutHandle, outHeader
  , openTamOutFile, openBamOutFile
  , closeOutHandle
  , put1
  )
       where

import Control.Concurrent.MVar
import Control.Exception (bracket, bracket_)
import Control.Monad
import Data.Bits
import qualified Data.ByteString.Char8 as BS
import Foreign
import Foreign.C.Types
import Foreign.C.String
import Foreign.ForeignPtr
import Foreign.Marshal.Array
import Foreign.Ptr
import Foreign.Storable

import qualified Data.Vector as V

import Bio.SamTools.Cigar
import Bio.SamTools.LowLevel

-- | Information about one target sequence in a SAM alignment set
data HeaderSeq = HeaderSeq { -- | Target sequence name 
                             name :: !BS.ByteString
                             -- | Target sequence lengh
                           , len :: !Int 
                           } deriving (Eq, Show, Ord)

-- | Target sequences from a SAM alignment set
newtype Header = Header { unHeader :: V.Vector HeaderSeq } deriving (Eq, Show)

-- | Number of target sequences
nTargets :: Header -> Int
nTargets = V.length . unHeader

-- | Returns a target sequence by ID, which is a 0-based index
targetSeqs :: Header -> Int -> Maybe HeaderSeq
targetSeqs h = (V.!?) (unHeader h)

-- | SAM/BAM format alignment
data Bam1 = Bam1 { ptrBam1 :: !(ForeignPtr Bam1Int)
                 , header :: !Header
                 }
            
-- | Target sequence ID in the target set
targetID :: Bam1 -> Int
targetID b = unsafePerformIO $ withForeignPtr (ptrBam1 b) getTID

-- | Target sequence name
targetName :: Bam1 -> BS.ByteString
targetName b = name $ (unHeader . header $ b) V.! (targetID b)

-- | Total length of the target sequence
targetLen :: Bam1 -> Int
targetLen b = len $ (unHeader . header $ b) V.! (targetID b)

-- | 0-based index of the leftmost aligned position on the target sequence
position :: Bam1 -> Int
position b = unsafePerformIO $ withForeignPtr (ptrBam1 b) getPos

isFlagSet :: BamFlag -> Bam1 -> Bool
isFlagSet f b = unsafePerformIO $ withForeignPtr (ptrBam1 b) $ liftM isfset . getFlag
  where isfset = (== f) . (.&. f)

-- | Is the read paired
isPaired :: Bam1 -> Bool
isPaired = isFlagSet flagPaired

-- | Is the pair properly aligned (usually based on relative orientation and distance)
isProperPair :: Bam1 -> Bool
isProperPair = isFlagSet flagProperPair

-- | Is the read unmapped
isUnmap :: Bam1 -> Bool
isUnmap = isFlagSet flagUnmap

-- | Is the read paired and the mate unmapped
isMateUnmap :: Bam1 -> Bool
isMateUnmap = isFlagSet flagMUnmap

-- | Is the fragment's reverse complement aligned to the target
isReverse :: Bam1 -> Bool
isReverse = isFlagSet flagReverse

-- | Is the read paired and the mate's reverse complement aligned to the target
isMateReverse :: Bam1 -> Bool
isMateReverse = isFlagSet flagMReverse

-- | Is the fragment from the first read in the template
isRead1 :: Bam1 -> Bool
isRead1 = isFlagSet flagRead1

-- | Is the fragment from the second read in the template
isRead2 :: Bam1 -> Bool
isRead2 = isFlagSet flagRead2

-- | Is the fragment alignment secondary
isSecondary :: Bam1 -> Bool
isSecondary = isFlagSet flagSecondary

-- | Did the read fail quality controls
isQCFail :: Bam1 -> Bool
isQCFail = isFlagSet flagQCFail

-- | Is the read a technical duplicate
isDup :: Bam1 -> Bool
isDup = isFlagSet flagDup

-- | CIGAR description of the alignment
cigars :: Bam1 -> [Cigar]
cigars b = unsafePerformIO $ withForeignPtr (ptrBam1 b) $ \p -> do
  nc <- getNCigar p
  liftM (map toCigar) $! peekArray nc . bam1Cigar $ p

-- | Name of the query sequence
queryName :: Bam1 -> BS.ByteString
queryName b = unsafePerformIO $ withForeignPtr (ptrBam1 b) (return . bam1QName)

-- | Length of the query sequence
queryLength :: Bam1 -> Int
queryLength b = unsafePerformIO $ withForeignPtr (ptrBam1 b) getLQSeq

-- | Query sequence
querySeq :: Bam1 -> BS.ByteString
querySeq b = unsafePerformIO $ withForeignPtr (ptrBam1 b) $ \p -> do
  l <- getLQSeq p
  let seqarr = bam1Seq p
  return $! BS.pack [ seqiToChar . bam1Seqi seqarr $ i | i <- [0..((fromIntegral l)-1)] ]

seqiToChar :: CUChar -> Char
seqiToChar = (chars V.!) . fromIntegral
  where chars = emptyChars V.// [(1, 'A'), (2, 'C'), (4, 'G'), (8, 'T'), (15, 'N')]
        emptyChars = V.generate 16 (\idx -> error $ "Unknown char " ++ show idx)

-- | Target ID of the mate alignment target sequence
mateTargetID :: Bam1 -> Int
mateTargetID b = unsafePerformIO $ withForeignPtr (ptrBam1 b) getMTID

-- | Name of the mate alignment target sequence
mateTargetName :: Bam1 -> BS.ByteString
mateTargetName b = name $ (unHeader . header $ b) V.! (mateTargetID b)

-- | Overall length of the mate alignment target sequence
mateTargetLen :: Bam1 -> Int
mateTargetLen b = len $ (unHeader . header $ b) V.! (mateTargetID b)

-- | 0-based coordinate of the left-most position in the mate alignment on the target
matePosition :: Bam1 -> Int
matePosition b = unsafePerformIO $ withForeignPtr (ptrBam1 b) getMPos

-- | Total fragment length
insertSize :: Bam1 -> Int
insertSize b = unsafePerformIO $ withForeignPtr (ptrBam1 b) getISize

-- | Handle for reading SAM/BAM format alignments
data InHandle = InHandle { inFilename :: !FilePath
                         , samfile :: !(MVar (Ptr SamFileInt))
                         , inHeader :: !Header -- ^ Target sequence set for the alignments
                         }
               
newInHandle :: FilePath -> Ptr SamFileInt -> IO InHandle
newInHandle filename fsam = do
  when (fsam == nullPtr) $ ioError . userError $ "Error opening BAM file " ++ show filename
  mv <- newMVar fsam
  addMVarFinalizer mv (finalizeSamFile mv)
  bhdr <- getSbamHeader fsam
  hdr <- convertHeader bhdr
  return $ InHandle { inFilename = filename, samfile = mv, inHeader = hdr }  

-- | Open a TAM (tab-delimited text) format file with @\@SQ@ headers
-- for the target sequence set.
openTamInFile :: FilePath -> IO InHandle
openTamInFile filename = sbamOpen filename "r" nullPtr >>= newInHandle filename
  
-- | Open a TAM format file with a separate target sequene set index
openTamInFileWithIndex :: FilePath -> FilePath -> IO InHandle
openTamInFileWithIndex filename indexname 
  = withCString indexname (sbamOpen filename "r" . castPtr) >>= newInHandle filename

-- | Open a BAM (binary) format file
openBamInFile :: FilePath -> IO InHandle
openBamInFile filename = sbamOpen filename "rb" nullPtr >>= newInHandle filename

finalizeSamFile :: MVar (Ptr SamFileInt) -> IO ()
finalizeSamFile mv = modifyMVar mv $ \fsam -> do
  unless (fsam == nullPtr) $ sbamClose fsam
  return (nullPtr, ())

-- | Close a SAM/BAM format alignment input handle
-- 
-- Target sequence set data is still available after the file input
-- has been closed.
closeInHandle :: InHandle -> IO ()
closeInHandle = finalizeSamFile . samfile

convertHeader :: BamHeaderPtr -> IO Header
convertHeader bhdr = do
  ntarg <- getNTargets bhdr
  names <- getTargetName bhdr
  lens <- getTargetLen bhdr
  hseqs <- forM [0..((fromIntegral ntarg)-1)] $ \idx -> do
    h <- peek (advancePtr names idx) >>= BS.packCString
    l <- peek (advancePtr lens idx)
    return $ HeaderSeq h (fromIntegral l)
  return . Header $! V.fromList hseqs
  
-- | Reads one alignment from an input handle, or returns @Nothing@ for end-of-file
get1 :: InHandle -> IO (Maybe Bam1)
get1 inh = withMVar (samfile inh) $ \fsam -> do
  b <- bamInit1
  res <- sbamRead fsam b 
  if res < 0
     then do bamDestroy1 b
             if res < -1
                then ioError . userError $ "Error reading from BAM file " ++ show (inFilename inh)
                else return Nothing
    else do bptr <- newForeignPtr bamDestroy1Ptr b
            return . Just $ Bam1 { ptrBam1 = bptr, header = inHeader inh }

data OutHandle = OutHandle { outFilename :: !FilePath
                           , outfile :: !(MVar (Ptr SamFileInt))
                           , outHeader :: !Header -- ^ Target sequence set for the alignments
                           }

withHeader :: Header -> (BamHeaderPtr -> IO a) -> IO a
withHeader (Header hdr) m = bracket bamHeaderInit bamHeaderDestroy $ \bhdr -> 
  withMany BS.useAsCString (V.toList . V.map name $ hdr) $ \namelist ->
  withArray namelist $ \names ->
  withArray (V.toList . V.map (fromIntegral . len) $ hdr) $ \lens -> 
  bracket_ (setNTargets bhdr . fromIntegral . V.length $ hdr) (setNTargets bhdr 0) $ 
  bracket_ (setTargetName bhdr names) (setTargetName bhdr nullPtr) $
  bracket_ (setTargetLen bhdr lens) (setTargetLen bhdr nullPtr) $
  m bhdr

newOutHandle :: String -> FilePath -> Header -> IO OutHandle
newOutHandle mode filename hdr = do
  fsam <- withHeader hdr $ sbamOpen filename mode . castPtr
  when (fsam == nullPtr) $ ioError . userError $ "Error opening BAM file " ++ show filename
  mv <- newMVar fsam
  addMVarFinalizer mv (finalizeSamFile mv)
  return $ OutHandle { outFilename = filename, outfile = mv, outHeader = hdr }
  
openTamOutFile :: FilePath -> Header -> IO OutHandle
openTamOutFile = newOutHandle "wh"

openBamOutFile :: FilePath -> Header -> IO OutHandle
openBamOutFile = newOutHandle "wb"
  
closeOutHandle :: OutHandle -> IO ()
closeOutHandle = finalizeSamFile . outfile

put1 :: OutHandle -> Bam1 -> IO ()
put1 outh b = withMVar (outfile outh) $ \fsam -> 
  withForeignPtr (ptrBam1 b) $ \p ->
  sbamWrite fsam p >>= handleRes
    where handleRes res | res > 0 = return ()
                        | res <= 0 = ioError . userError $ "Error writing to BAM file " ++ show (outFilename outh)
 