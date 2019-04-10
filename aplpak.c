/* **************************************************************************
// **************************************************************************
//
// APLPAK.C
//
// This simple utility uses Jorgen Ibsen's freeware aPLib library to compress
// one or more data-files into a single compressed container-file.
//
// aPLib's compressed data is simple-and-fast to decompress on 8-bit or higher
// processors, and the container-file format is useful for game development on
// all platforms from the 1980's to the current day.
//
// Copyright John Brandwood 2019.
//
// Distributed under the Boost Software License, Version 1.0.
// (See accompanying file LICENSE_1_0.txt or copy at
//  http://www.boost.org/LICENSE_1_0.txt)
//
// **************************************************************************
// **************************************************************************
//
// This product uses the aPLib compression library,
// Copyright (c) 1998-2014 Joergen Ibsen, All Rights Reserved.
// For more information, please visit: http://www.ibsensoftware.com/
//
// **************************************************************************
// **************************************************************************
//
// Output File Format ...
//
//   Header :
//  
//     byte : 'a'
//     byte : 'p'
//     byte : 'k'
//     byte : Format Option Flags (currently zero).
//  
//   Table  : (1 entry per compressed file, plus 1 for total file size).
//  
//     byte : Bits  0...7 of chunk offset from start of file.
//     byte : Bits  8..15 of chunk offset from start of file.
//     byte : Bits 16..23 of chunk offset from start of file.
//     byte : Decompressed size in 256-byte increments.
//  
//   Chunk  : (1 chunk per compressed file, padded to next 32-bit boundary)
//  
//     byte : aPLib data stream
//
// **************************************************************************
// **************************************************************************
*/

#include "elmer.h"

#define VERSION_STR "aplpak v0.1.0 (" __DATE__ ")"



/* **************************************************************************
// **************************************************************************
//
// CompressAPLib ()
//
// Compress data with Joergen Ibsen's aPLib.
//
*/

#include "aplib.h"

uint8_t * CompressAPLib (
  uint8_t * pSrcBuffer, unsigned uSrcLength,
  uint8_t * pDstBuffer, unsigned uDstLength)

{
  static size_t    uWorkBuf = 0;
  static uint8_t * pWorkBuf = NULL;

  size_t uCompressedLength;

  if ((pWorkBuf == NULL) || (aP_workmem_size(uSrcLength) > uWorkBuf))
  {
    if (pWorkBuf) free(pWorkBuf);

    uWorkBuf = aP_workmem_size(uSrcLength);
    pWorkBuf = (uint8_t *) malloc( uWorkBuf );

    if (pWorkBuf == NULL)
    {
      return NULL;
    }
  }

  uCompressedLength =
    aP_pack( pSrcBuffer, pDstBuffer, uSrcLength, pWorkBuf, NULL, NULL );

  if (uCompressedLength == APLIB_ERROR)
  {
    return NULL;
  }

  pDstBuffer += uCompressedLength;

  // All done.

  return (pDstBuffer);
}



/* **************************************************************************
// **************************************************************************
//
// ReadBinaryFile ()
//
// Uses POSIX file functions rather than C file functions.
//
// Google "FIO19-C" for the reason why.
//
// N.B. Will return an error for files larger than 2GB on a 32-bit system.
*/

bool ReadBinaryFile ( const char * pName, uint8_t ** pBuffer, size_t * pLength )
{
  uint8_t *   pData = NULL;
  off_t       uSize;
  struct stat cStat;

  int hFile = open( pName, O_BINARY | O_RDONLY );

  if (hFile == -1)
    goto errorExit;

  if ((fstat( hFile, &cStat ) != 0) || (!S_ISREG( cStat.st_mode )))
    goto errorExit;

  if (cStat.st_size > SSIZE_MAX)
    goto errorExit;

  uSize = cStat.st_size;

  pData = (uint8_t *) malloc( uSize );

  if (pData == NULL)
    goto errorExit;

  if (read( hFile, pData, uSize ) != uSize)
    goto errorExit;

  close( hFile );

  *pBuffer = pData;
  *pLength = uSize;

  return true;

  // Handle errors.

  errorExit:

    if (pData != NULL) free( pData );
    if (hFile >= 0) close( hFile );

    *pBuffer = NULL;
    *pLength = 0;

    return false;
}



/* **************************************************************************
// **************************************************************************
//
// WriteBinaryFile ()
//
// Uses POSIX file functions rather than C file functions, just because
// it might save some space since ReadBinaryFile() uses POSIX functions.
*/

bool WriteBinaryFile ( const char * pName, uint8_t * pBuffer, size_t iLength )
{
  int hFile = open( pName, O_CREAT | O_BINARY | O_WRONLY );

  if (hFile == -1)
    goto errorExit;

  if (write( hFile, pBuffer, iLength ) != iLength)
    goto errorExit;

  close( hFile );

  return true;

  // Handle errors.

  errorExit:

    if (hFile >= 0) close( hFile );

    return false;
}



/* **************************************************************************
// **************************************************************************
//
// main ()
//
*/

#define MAX_FILES 256

int main(int argc, char* argv[])
{
  /* Local Variables. */

  char *           aNameString[MAX_FILES];
  int              aNameLength[MAX_FILES];

  bool             bShowHelp = false;
  int              iArg = 1;
  int              i, iFileCount, iChunkCount, iOutputFile;

  size_t           iDataTotal, iFileOffset, iRemainingSpace;

  uint8_t *        pCompressedData;
  uint8_t *        pCompressedHead;

  /* Make these static so that they are zero-initialized. */

  static uint8_t * aFileBuffer[MAX_FILES];
  static size_t    aFileLength[MAX_FILES];
  static uint8_t * pSyscard;

  /* Read through any options on the command line. */

  while (iArg < argc)
  {
    if (argv[iArg][0] != '-') break;

    switch (tolower(argv[iArg][1]))
    {
      case 'h':
        bShowHelp = true;
        break;
      default:
        printf("Unknown option \"%s\", aborting!\n");
        goto errorExit;
    }

    iArg += 1;
  }

  /* Show the help information if called incorrectly (too many or too few arguments). */

  if (bShowHelp || (argc < (iArg+2)) || (argc > (iArg+2)))
  {
    printf("\n%s by J.C.Brandwood\n\n", VERSION_STR);

    puts(
      "This utility uses Jorgen Ibsen's freeware aPLib library to compress\n"
      "one or more input-files into a single compressed output-file.\n"
      "\n"
      "Usage   : aplpak [<options>] {<input-file> ...} <output-file>\n"
      "\n"
      "Options :\n"
      "  -h      Print this help message\n"
      );
    goto errorExit;
  }

  /* Count how many filenames are on the command line. */

  iFileCount = argc - iArg;

  if (iFileCount > MAX_FILES)
  {
    puts("Too many files, aborting!\n");
    goto errorExit;
  }

  iChunkCount = iFileCount - 1;
  iOutputFile = iFileCount - 1;

  /* Strip double-quote characters from strings. */

  for (i = 0; i < iFileCount; ++i)
  {
    char * pString = argv[iArg+i];
    int    iLength = (int) strlen(pString);

    if (*pString == '\"')
    {
      if (iLength < 2 || pString[iLength-1] != '\"')
      {
        puts("Malformed string, aborting!\n");
        goto errorExit;
      }
      pString += 1;
      iLength -= 1;

      pString[iLength-1] = '\0';
    }

    aNameString[i] = pString;
    aNameLength[i] = iLength;
  }

  /* Load the input files into memory. */

  iDataTotal = 0;

  for (i = 0; i < iOutputFile; ++i)
  {
    if (!ReadBinaryFile( aNameString[i], &(aFileBuffer[i]), &(aFileLength[i]) ))
    {
      printf( "Failed to load file \"%s\" into memory!\n", aNameString[i] );
      goto errorExit;
    }
    iDataTotal += aFileLength[i];
  }

  /* Allocate space for the compressed data. */

  aFileLength[iOutputFile] = (iDataTotal * 9) / 8;
  aFileBuffer[iOutputFile] = malloc(aFileLength[iOutputFile]);

  if (aFileBuffer[iOutputFile] == NULL)
  {
    printf( "Cannot allocate memory for the compressed file, aborting!\n" );
    goto errorExit;
  }

  /* Write out the file header (i.e. identifier). */

  pCompressedData = aFileBuffer[iOutputFile];

  *pCompressedData++ = 'a';
  *pCompressedData++ = 'p';
  *pCompressedData++ = 'k';

  /* Write out the compression options (currently none). */

  *pCompressedData++ = 0x00;

  /* Calc start of file index table. */

  pCompressedHead = pCompressedData;

  /* Calc start of compressed files. */

  pCompressedData += 4 * (iChunkCount + 1);

  /* Compress the input file(s). */

  for (i = 0; i < iChunkCount; ++i)
  {
    /* Calculate the chunk offset from the start of the file. */

    iFileOffset = pCompressedData - aFileBuffer[iOutputFile];

    /* Write out the chunk offset (16MB maximum). */

    pCompressedHead[0] = 255 & ((iFileOffset) >>  0);
    pCompressedHead[1] = 255 & ((iFileOffset) >>  8);
    pCompressedHead[2] = 255 & ((iFileOffset) >> 16);

    /* Write out the approximate chunk length (in 256-byte increments). */

    pCompressedHead[3] = 255 & ((aFileLength[i] + 255) >> 8);

    pCompressedHead += 4;

    /* Compress the data. */

    iRemainingSpace =
      (aFileBuffer[iOutputFile] + aFileLength[iOutputFile]) - pCompressedData;

    pCompressedData = CompressAPLib( aFileBuffer[i],
                                     aFileLength[i],
                                     pCompressedData,
                                     iRemainingSpace);

    if (pCompressedData == NULL)
    {
      printf("Unknown error while compressing the data, aborting!\n");
      goto errorExit;
    }

    /* Pad the compressed chunk to the next 16-bit boundary. */

    if (1 & (pCompressedData - aFileBuffer[iOutputFile]))
    {
      *pCompressedData++ = 0;
    }

    /* Pad the compressed chunk to the next 32-bit boundary. */

    if (2 & (pCompressedData - aFileBuffer[iOutputFile]))
    {
      *pCompressedData++ = 0;
      *pCompressedData++ = 0;
    }
  }

  /* Calculate the End-Of-File offset from the start of the file. */

  iFileOffset = pCompressedData - aFileBuffer[iOutputFile];

  /* Write out the End-Of-File offset (16MB maximum). */

  pCompressedHead[0] = 255 & ((iFileOffset) >>  0);
  pCompressedHead[1] = 255 & ((iFileOffset) >>  8);
  pCompressedHead[2] = 255 & ((iFileOffset) >> 16);
  pCompressedHead[3] = 0;

  pCompressedHead += 4;

  /* Write out the compressed file. */

  if (!WriteBinaryFile( aNameString[iOutputFile],
                        aFileBuffer[iOutputFile],
                        pCompressedData - aFileBuffer[iOutputFile]))
  {
    printf( "Failed to write the compressed file!\n" );
    goto errorExit;
  }

  /* Print out the results so that they can be . */

  return 0;

  errorExit:

    exit(EXIT_FAILURE);
}
